%% AltitudeMonitor.m
% Health + conditioning state machine for altitude measurements.
% States: OK, SUSPECT, FAILED
%
% Input: Measured altitude from AltitudeSensorSITL
% Output: Conditioned altitude and sensor health state

classdef AltitudeMonitor < handle
    properties
        % Timing
        Fs (1,1) double = 50;
        dt (1,1) double = 0.02;

        % Valid range
        AltMin (1,1) double = -500;
        AltMax (1,1) double = 20000;

        % Threshold edge band for "noise excursions near threshold"
        NearThreshBand (1,1) double = 50; % [m]

        % Conditioning 
        LPFAlpha (1,1) double = 0.15;     % 0..1
        MaxClimbRate (1,1) double = 80;   % [m/s]

        % State machine timing (seconds)
        T_stable (1,1) double = 1.0;
        T_fail   (1,1) double = 0.5;
        T_recover(1,1) double = 2.0;

        % Spike/dropout detection
        SpikeDelta (1,1) double = 75;        % [m]
        DropoutHoldTime (1,1) double = 0.1;  % [s] (kept for completeness; NaN is treated as dropout)
    end

    properties (SetAccess = private)
        % Outputs
        State (1,1) string = "OK";        % "OK" | "SUSPECT" | "FAILED"

        Raw (1,1) double = NaN;           % last raw measurement seen by monitor
        Cond (1,1) double = NaN;          % conditioned altitude

        IsValid (1,1) logical = false;    % validity this step
        HealthFlags struct                 % diagnostic flags
    end

    properties (Access = private)
        % Internal memory/timers
        t_sinceNormal double = 0;
        t_sinceInvalid double = 0;
        t_sinceRecoverCandidate double = 0;

        lastRaw double = NaN;
        lastCond double = NaN;
        lastValidRaw double = NaN;

        sawDataReturn logical = false;

        dtWasExplicitlySet (1,1) logical = false;
    end

    methods
        function obj = AltitudeMonitor(varargin)
            % Name-value init
            for k = 1:2:numel(varargin)
                name = varargin{k};
                val  = varargin{k+1};

                if strcmpi(name, "dt")
                    obj.dtWasExplicitlySet = true;
                end

                obj.(name) = val;
            end

            if ~obj.dtWasExplicitlySet
                obj.dt = 1/obj.Fs;
            end

            obj.HealthFlags = obj.defaultFlags();
        end

        function obj = set.Fs(obj, newFs)
            obj.Fs = newFs;
            if ~obj.dtWasExplicitlySet
                obj.dt = 1/obj.Fs;
            end
        end

        function obj = set.dt(obj, newDt)
            obj.dt = newDt;
            obj.dtWasExplicitlySet = true;
        end

        function [altCond, state, flags] = step(obj, altitudeMeasurement)
            % altitudeMeasurement is the sensor output (may be noisy, NaN, etc. depending on injector)

            dt = obj.dt;

            raw = altitudeMeasurement;
            obj.Raw = raw;

            % Validity checks (FR-03)
            isFinite = isfinite(raw);
            inRange = isFinite && (raw >= obj.AltMin) && (raw <= obj.AltMax);
            obj.IsValid = inRange;

            dropout = ~isFinite; % NaN/Inf treated as dropout/no-signal

            spike = false;
            if isFinite && isfinite(obj.lastRaw)
                spike = abs(raw - obj.lastRaw) >= obj.SpikeDelta;
            end

            nearThresh = false;
            if isFinite
                nearThresh = (raw - obj.AltMin) <= obj.NearThreshBand || (obj.AltMax - raw) <= obj.NearThreshBand;
            end

            % Same condition: near threshold AND (spike OR not inRange)
            noiseExcursionNearThreshold = nearThresh && (spike || ~inRange);

            % Timers
            if inRange && ~spike
                obj.t_sinceNormal = obj.t_sinceNormal + dt;
            else
                obj.t_sinceNormal = 0;
            end

            if ~inRange || dropout
                obj.t_sinceInvalid = obj.t_sinceInvalid + dt;
            else
                obj.t_sinceInvalid = 0;
            end

            if inRange
                obj.lastValidRaw = raw;
            end

            % Conditioning (FR-02)
            rawForCond = raw;
            if ~inRange
                rawForCond = obj.lastValidRaw; % hold last valid if invalid/dropout
            end

            if ~isfinite(obj.lastCond)
                cond = rawForCond;
            else
                % Low-pass filter
                condLP = obj.lastCond + obj.LPFAlpha * (rawForCond - obj.lastCond);

                % Rate limit
                maxStep = obj.MaxClimbRate * dt;
                delta = condLP - obj.lastCond;
                delta = max(-maxStep, min(maxStep, delta));
                cond = obj.lastCond + delta;
            end

            obj.Cond = cond;

            % Flags
            flags = obj.defaultFlags();
            flags.valid = inRange;
            flags.outOfRange = isFinite && ~inRange;
            flags.dropout = dropout;
            flags.spike = spike;
            flags.noiseExcursionNearThreshold = noiseExcursionNearThreshold;

            % State machine (FR-04)
            switch obj.State
                case "OK"
                    if flags.outOfRange || flags.dropout || flags.spike || flags.noiseExcursionNearThreshold
                        obj.State = "SUSPECT";
                        obj.t_sinceNormal = 0;
                    end

                    if obj.t_sinceInvalid >= obj.T_fail
                        obj.State = "FAILED";
                        obj.sawDataReturn = false;
                        obj.t_sinceRecoverCandidate = 0;
                    end

                case "SUSPECT"
                    if obj.t_sinceInvalid >= obj.T_fail
                        obj.State = "FAILED";
                        obj.sawDataReturn = false;
                        obj.t_sinceRecoverCandidate = 0;
                    end

                    if obj.t_sinceNormal >= obj.T_stable
                        obj.State = "OK";
                    end

                case "FAILED"
                    % FAILED -> SUSPECT when clean data returns (needs validating again)
                    if inRange && ~spike
                        if ~obj.sawDataReturn
                            obj.sawDataReturn = true;
                            obj.State = "SUSPECT";
                            obj.t_sinceNormal = 0;
                            obj.t_sinceRecoverCandidate = 0;
                        end
                    end
            end

            % Post-fail stricter revalidation window (FAILED->SUSPECT->OK)
            if obj.State == "SUSPECT" && obj.sawDataReturn
                if inRange && ~spike
                    obj.t_sinceRecoverCandidate = obj.t_sinceRecoverCandidate + dt;
                else
                    obj.t_sinceRecoverCandidate = 0;
                end

                if obj.t_sinceRecoverCandidate >= obj.T_recover
                    obj.State = "OK";
                    obj.sawDataReturn = false;
                    obj.t_sinceRecoverCandidate = 0;
                end
            end

            % Save history
            obj.lastRaw = raw;
            obj.lastCond = cond;

            % Publish
            obj.HealthFlags = flags;
            altCond = obj.Cond;
            state = obj.State;
        end
    end

    methods (Access = private)
        function flags = defaultFlags(~)
            flags = struct( ...
                "valid", false, ...
                "outOfRange", false, ...
                "dropout", false, ...
                "spike", false, ...
                "noiseExcursionNearThreshold", false);
        end
    end
end