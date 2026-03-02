classdef SimpleInjector < handle
    % SimpleInjector
    % Minimal fault injector aligned to FR-10 failure classes:
    %  (a) stuck-at, (b) bias/offset, (c) drift, (d) dropout/spike
    %
    % Interface:
    %   y = apply(x, dt)
    %   or [y, meta] = apply(x, dt)   % meta optional

    properties
        Seed (1,1) double = NaN

        % Always-on measurement noise (optional)
        NoiseSigma (1,1) double = 0.0

        % Fault start rate (approx) [1/s]
        FaultRatePerSecond (1,1) double = 0.0

        % How long a fault lasts once started
        FaultDurationSeconds (1,1) double = 0.5

        % If true, faults latch once started (never recover)
        LatchFault (1,1) logical = false

        % Relative selection weights for fault classes (set to 0 to disable)
        W_Stuck  (1,1) double = 1
        W_Bias   (1,1) double = 1
        W_Drift  (1,1) double = 1
        W_Dropout(1,1) double = 1
        W_Spike  (1,1) double = 1

        % Magnitudes (units are the sensor's units)
        BiasMagnitude (1,1) double = 0.0          % constant offset during bias fault
        DriftRateMagnitude (1,1) double = 0.0     % units per second during drift
        SpikeMagnitude (1,1) double = 0.0         % one-time jump when spike fault starts

        % Dropout output behaviour
        DropoutAsNaN (1,1) logical = true
    end

    properties (Access = private)
        rngInit (1,1) logical = false

        faultActive (1,1) logical = false
        faultType (1,1) string = "NONE"
        tLeft (1,1) double = 0

        % fault state
        stuckValue double = NaN
        biasValue (1,1) double = 0
        driftRate (1,1) double = 0
        driftAccum (1,1) double = 0
        spikeDone (1,1) logical = false
    end

    methods
        function obj = SimpleInjector(varargin)
            for k = 1:2:numel(varargin)
                obj.(varargin{k}) = varargin{k+1};
            end
        end

        function [y, meta] = apply(obj, x, dt)
            obj.ensureRng();

            % Update fault timer (unless latched)
            if obj.faultActive && ~obj.LatchFault
                obj.tLeft = obj.tLeft - dt;
                if obj.tLeft <= 0
                    obj.clearFault();
                end
            end

            % Roll dice to START a fault (only if none active)
            if ~obj.faultActive && obj.FaultRatePerSecond > 0
                pStep = 1 - exp(-obj.FaultRatePerSecond * dt);
                if rand() < pStep
                    obj.startFault(x);
                end
            end

            % Base measurement = input + Gaussian noise
            y = x;
            if obj.NoiseSigma > 0
                y = y + obj.NoiseSigma * randn();
            end

            % Apply active fault
            if obj.faultActive
                switch obj.faultType
                    case "STUCK"
                        y = obj.stuckValue;

                    case "BIAS"
                        y = y + obj.biasValue;

                    case "DRIFT"
                        obj.driftAccum = obj.driftAccum + obj.driftRate * dt;
                        y = y + obj.driftAccum;

                    case "DROPOUT"
                        if obj.DropoutAsNaN
                            y = NaN;
                        else
                            y = 0;
                        end

                    case "SPIKE"
                        if ~obj.spikeDone
                            y = y + obj.SpikeMagnitude * obj.randSign();
                            obj.spikeDone = true;
                        end
                end
            end

            % Optional metadata (handy for debugging / plots)
            meta = struct( ...
                "faultActive", obj.faultActive, ...
                "faultType", obj.faultType);
        end
    end

    methods (Access = private)
        function ensureRng(obj)
            if obj.rngInit, return; end
            if ~isnan(obj.Seed)
                rng(obj.Seed);
            end
            obj.rngInit = true;
        end

        function startFault(obj, xAtStart)
            obj.faultActive = true;
            obj.tLeft = obj.FaultDurationSeconds;
            obj.spikeDone = false;
            obj.driftAccum = 0;

            w = [obj.W_Stuck, obj.W_Bias, obj.W_Drift, obj.W_Dropout, obj.W_Spike];
            types = ["STUCK","BIAS","DRIFT","DROPOUT","SPIKE"];

            if all(w == 0)
                obj.faultType = "DROPOUT";
            else
                idx = obj.weightedChoice(w);
                obj.faultType = types(idx);
            end

            % Precompute fault parameters
            switch obj.faultType
                case "STUCK"
                    obj.stuckValue = xAtStart; % stuck-at the current value
                case "BIAS"
                    obj.biasValue = obj.BiasMagnitude * obj.randSign();
                case "DRIFT"
                    obj.driftRate = obj.DriftRateMagnitude * obj.randSign();
                otherwise
                    obj.biasValue = 0;
                    obj.driftRate = 0;
            end
        end

        function clearFault(obj)
            obj.faultActive = false;
            obj.faultType = "NONE";
            obj.tLeft = 0;
            obj.stuckValue = NaN;
            obj.biasValue = 0;
            obj.driftRate = 0;
            obj.driftAccum = 0;
            obj.spikeDone = false;
        end

        function s = randSign(~)
            if rand() < 0.5, s = -1; else, s = 1; end
        end

        function idx = weightedChoice(~, w)
            w = max(0, w(:)');
            c = cumsum(w);
            r = rand() * c(end);
            idx = find(r <= c, 1, "first");
        end
    end
end