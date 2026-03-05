
%% SensorOrchestrator.m
% System states: "NORMAL", "WARN", "FAULT"
% Sensor states: "OK", "SUSPECT", "FAIL"
%
% Rules:
% - FAULT if any safety-critical sensor == "FAIL" OR redundancy mismatch duration >= T_fault
% - WARN  if any sensor == "SUSPECT" OR any non-critical sensor == "FAIL"
%         OR redundancy mismatch duration >= T_redundancyThreshold
% - Otherwise NORMAL

classdef SensorOrchestrator < handle
    properties
        Fs (1,1) double = 20
        dt (1,1) double = 0.05

        T_warn (1,1) double = 0.5
        T_fault (1,1) double = 0.7
        T_redundancyThreshold (1,1) double = 0.2

        % Cooloff period after state transition
        T_cooldown (1,1) double = 0.5 

        % Time Threshold for FAIL -> WARN / FAULT recovery gating
        T_recover (1,1) double = 0.4
        % Time threshold for WARN -> CLEAR
        T_clear (1,1) double = 0.4

        mismatchThreshold (1,1) double = 0.1  % e.g. |altSlope - verticalSpeed|
        derivWindowSec (1,1) double = 0.5     % use altitude from ~0.5s ago

        logger = []
    end

    properties (SetAccess = private)
        State (1,1) string = "NORMAL"
        PrevState (1,1) string = "NORMAL"

        % Redundancy tracking
        RedundancyMismatch (1,1) logical = false
        RedundancyMismatchDuration (1,1) double = 0  % seconds

        % Altitude history for slope estimation
        AltitudeHistory (:,1) double = []

        % Cooldown timer & flag
        cooldownPeriod (1,1) double = 0 

        stateChangePossibleFlag (1,1) logical = true

        % Latch to store if Log file has been made for this run
        LogEnabled = false
    end

    properties (Access = private)

        % init flag
        hasFirstValid (1,1) logical = false

        % timers
        tClear   (1,1) double = 0
        tRecover (1,1) double = 0
        tRedMis  (1,1) double = 0
        tRedSev  (1,1) double = 0
    
        state (1,1) string = "INIT"
    end

    methods
        function obj = SensorOrchestrator(varargin)
            % Name-value init
            dtWasSet = false;

            for k = 1:2:numel(varargin)
                name = varargin{k};
                val  = varargin{k+1};

                if strcmpi(name,"dt"), dtWasSet = true; end
                obj.(name) = val;
            end

            if ~dtWasSet
                obj.dt = 1/obj.Fs;
            end
        end

        function reset(obj)
            obj.State = "NORMAL";
            obj.PrevState = "NORMAL";
            obj.RedundancyMismatch = false;
            obj.RedundancyMismatchDuration = 0;
            obj.AltitudeHistory = [];

            % keep private state machine consistent after reset
            obj.state = "INIT";
            obj.hasFirstValid = false;

            % reset transition timers
            obj.tClear = 0; obj.tRecover = 0;
            obj.tRedMis = 0; obj.tRedSev = 0;
        end

        function [state, logMsg, diagnostics] = step(obj, states, values, tt)
            obj.PrevState = obj.State;
            logMsg = "";

            % Keep external State in sync with internal state machine
            if obj.state ~= obj.State
                obj.state = obj.State;
            end

            % 1) Update altitude history
            obj.pushAltitude(values.Altitude);

            % 2) Compute redundancy mismatch (altitude slope vs vertical speed)
            obj.RedundancyMismatch = obj.computeRedundancyMismatch(values);

            % 3) Update redundancy mismatch duration timer
            if obj.RedundancyMismatch
                obj.RedundancyMismatchDuration = obj.RedundancyMismatchDuration + obj.dt;
            else
                obj.RedundancyMismatchDuration = 0;
            end

            % 4) Compute "facts"
            criticalStates = [ ...
                string(states.AltitudeSensor), ...
                string(states.AirspeedSensor), ...
                string(states.VerticalSpeedSensor), ...
                string(states.PitchSensor), ...
                string(states.RollSensor) ];

            nonCriticalStates = [ ...
                string(states.TemperatureSensor), ...
                string(states.PressureSensor) ];

            allStates = [criticalStates, nonCriticalStates];

            % tolerate either "FAIL" or "FAILED" for robustness
            isFail = (allStates == "FAIL") | (allStates == "FAILED");

            criticalFailNow    = any((criticalStates == "FAIL") | (criticalStates == "FAILED"));
            nonCriticalFailNow = any((nonCriticalStates == "FAIL") | (nonCriticalStates == "FAILED"));
            anyFailNow         = any(isFail);
            anySuspectNow      = any(allStates == "SUSPECT");

            % "all OK" means ALL are OK
            allOK              = all(allStates == "OK");

            % Redundancy "now" flags based on duration (kept for diagnostics)
            redundancyWarnNow  = obj.RedundancyMismatchDuration >= obj.T_redundancyThreshold;
            redundancyFaultNow = obj.RedundancyMismatchDuration >= obj.T_fault;

            % State transitions can only occur after fixed cooldowns (no
            % hysteresis implemented to account for noise/fluctuation
            % THIS IS A CONSTRAINT
            
            if obj.RedundancyMismatch
                obj.tRedMis = obj.tRedMis + obj.dt; 
                obj.tRedSev = obj.tRedMis + obj.dt; 
            else
                obj.tRedMis = 0;
                obj.tRedSev = 0;
            end

                % State machine for state transitions
                %% TODO: Add redundancy mismatch into state transition conditions
                switch obj.state
                    % If in normal, check if FAULT has been present for >
                    % T_recover
                    case "FAULT"
                        if obj.tRecover >= obj.T_recover
                            % We can move

                            % Check transition to warn
                            if ~anyFailNow && anySuspectNow
                                obj.state = "WARN"; 
    
                            % Check transition to normal
                            elseif ~anyFailNow && ~anySuspectNow
                                obj.state = "NORMAL";

                            end 

                        else
                            % Add to timer
                            obj.tRecover = obj.tRecover + obj.dt; 
                        end 

                    case "WARN"
                        % Check if we have been longer than T_clear
                        if obj.tClear >= obj.T_clear
                            % We can move

                            % Check transition to Fault
                            if anyFailNow | obj.tRedSev >= obj.T_fault
                                obj.state = "FAULT"
    
                            % Check transition to normal
                            elseif allOK && ~redundancyFaultNow && ~redundancyWarnNow
                                obj.state = "NORMAL"; 
    
                            end
                        else 
                            % If not, add to timer 
                            obj.tClear = obj.T_clear + obj.dt; 
                        end

                    case "NORMAL"
                         % Check transition to fault
                        if anyFailNow | obj.tRedSev >= obj.T_fault 
                            obj.state = "FAULT"; 

                        % Check transition to warn
                        elseif ~anyFailNow && anySuspectNow | obj.tRedMis > obj.T_warn
                            obj.state = "WARN"; 

                        end
                end 
               


            % publish internal state machine state outward
            obj.State = obj.state;

            % Logging (only when state changes)
            if obj.State ~= obj.PrevState && ~isempty(obj.logger)
                prevState = obj.PrevState;
                time = string(datetime("now"), "dd:MM:yyyy HH:mm:ss.SSS");
                newState = obj.State;
                obj.logger.logStateChange(prevState, time, tt, newState);
            end

            % Diagnostics output
            diagnostics = struct();
            diagnostics.criticalFailNow = criticalFailNow;
            diagnostics.nonCriticalFailNow = nonCriticalFailNow;
            diagnostics.anySuspectNow = anySuspectNow;
            diagnostics.redundancyMismatch = obj.RedundancyMismatch;
            diagnostics.redundancyMismatchDuration = obj.RedundancyMismatchDuration;
            diagnostics.redundancyWarnNow = redundancyWarnNow;
            diagnostics.redundancyFaultNow = redundancyFaultNow;

            state = obj.State;
        end 
    end 

    methods (Access = private)
        function pushAltitude(obj, altitude)
            nKeep = max(2, ceil(obj.derivWindowSec / obj.dt) + 1);

            obj.AltitudeHistory(end+1,1) = altitude;

            if numel(obj.AltitudeHistory) > nKeep
                obj.AltitudeHistory(1:(end-nKeep)) = [];
            end
        end

        function mismatch = computeRedundancyMismatch(obj, values)
            nBack = round(obj.derivWindowSec / obj.dt);
            if numel(obj.AltitudeHistory) <= nBack
                mismatch = false;
                return;
            end

            altNow = obj.AltitudeHistory(end);
            altPast = obj.AltitudeHistory(end - nBack);

            altSlope = (altNow - altPast) / (nBack * obj.dt);
            vs = values.VerticalSpeed;

            mismatch = abs(altSlope - vs) > obj.mismatchThreshold;
        end
    end
end