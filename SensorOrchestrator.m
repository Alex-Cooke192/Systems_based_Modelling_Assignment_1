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

        % Latch to store if Log file has been made for this run
        LogEnabled = false
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
        end

        function [state, logMsg, diagnostics] = step(obj, states, values, tt)
            % states: struct with fields (strings): AltitudeSensor, AirspeedSensor,
            %         VerticalSpeedSensor, PitchSensor, RollSensor,
            %         TemperatureSensor, PressureSensor
            %
            % values: struct with fields (doubles): Altitude, VerticalSpeed

            obj.PrevState = obj.State;
            % Set default
            nextState = obj.State; 
            logMsg = "";

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

            criticalFailNow    = any(criticalStates == "FAIL");
            nonCriticalFailNow = any(nonCriticalStates == "FAIL");
            anySuspectNow      = any(allStates == "SUSPECT");

            redundancyWarnNow  = obj.RedundancyMismatchDuration >= obj.T_redundancyThreshold;
            redundancyFaultNow = obj.RedundancyMismatchDuration >= obj.T_fault;

            % 5) Decide next system state 
            if obj.State == "FAULT"
                % If no fails but at least one SUSPECT -> WARN
                if ~criticalFailNow && ~nonCriticalFailNow && anySuspectNow
                    nextState = "WARN";

                % If no fails and all SensorHealth == OK -> NORMAL
                elseif ~criticalFailNow && ~nonCriticalFailNow && ~anySuspectNow
                    nextState = "NORMAL"; 

                else 
                    % No change
                    nextState = "FAULT"; 
                end
                
            elseif obj.State == "WARN"
                % If all SENSORHEALTH = OK and RedundancyMismatch -> NORMAL
                if ~criticalFailNow && ~nonCriticalFailNow && ~anySuspectNow
                    if ~redundancyFaultNow && ~redundancyWarnNow
                        nextState = "NORMAL"; 
                    end  

                % If any safety-critical sensorHelath == FAILED or
                % ReundancyMismatchDuration > T_redundancThreshold -> FAULT
                elseif criticalFailNow || redundancyFaultNow
                    nextState = "FAULT";
                else
                    % No change
                    nextState = "WARN"; 
                end 

          
            else 
                if criticalFailNow || redundancyFaultNow
                    nextState = "FAULT";
                elseif anySuspectNow || nonCriticalFailNow || redundancyWarnNow
                    nextState = "WARN";
                else
                    nextState = "NORMAL";
                end
            end

            obj.State = nextState;

            % 6) Logging (only when state changes)
            if obj.State ~= obj.PrevState
                prevState = obj.PrevState; 
                time = string(datetime("now"), "dd:MM:yyyy HH:mm:ss.SSS"); 
                newState = obj.State; 
                obj.logger.logStateChange(prevState, time, tt, newState)
            end

            % 7) Diagnostics output
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
            % Keep enough samples to cover derivWindowSec
            nKeep = max(2, ceil(obj.derivWindowSec / obj.dt) + 1);

            obj.AltitudeHistory(end+1,1) = altitude;

            if numel(obj.AltitudeHistory) > nKeep
                obj.AltitudeHistory(1:(end-nKeep)) = [];
            end
        end

        function mismatch = computeRedundancyMismatch(obj, values)
            % If not enough history, can't compute slope reliably yet
            nBack = round(obj.derivWindowSec / obj.dt);
            if numel(obj.AltitudeHistory) <= nBack
                mismatch = false;
                return;
            end

            altNow = obj.AltitudeHistory(end);
            altPast = obj.AltitudeHistory(end - nBack);

            altSlope = (altNow - altPast) / (nBack * obj.dt); % units of altitude per second
            vs = values.VerticalSpeed;

            mismatch = abs(altSlope - vs) > obj.mismatchThreshold;
        end
    end
end