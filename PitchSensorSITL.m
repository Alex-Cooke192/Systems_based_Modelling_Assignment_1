%% PitchSensorSITL.m
% Dumb SITL pitch sensor emulator:
% - Takes an input pitch value each step()
% - Optionally applies an Injector (noise/faults)
% - Outputs the resulting value
% - NO filtering, NO conditioning, NO range checks, NO health/state machine

classdef PitchSensorSITL < handle
    properties
        Fs (1,1) double = 50;
        dt (1,1) double = 1/Fs;

        % Optional external injector (noise + faults)
        % Set to [] for none, or a handle object with method:
        %   y = apply(x, dt)
        %   OR: [y, inj] = apply(x, dt)   (2nd output ignored here)
        Injector = [];
    end

    properties (SetAccess = private)
        Raw (1,1) double = NaN;   % last input received
        Out (1,1) double = NaN;   % last output after injector
    end

    methods
        function obj = PitchSensorSITL(varargin)
            % Name-value init
            for k = 1:2:numel(varargin)
                obj.(varargin{k}) = varargin{k+1};
            end
            if isempty(obj.dt) || obj.dt <= 0
                obj.dt = 1/obj.Fs;
            end
        end

        function y = step(obj, truePitchDeg, tNow)
            %#ok<INUSD>
            % step() takes "truePitchDeg" from plant/sim and returns a raw/noisy measurement.

            obj.Raw = truePitchDeg;

            yOut = truePitchDeg;

            % Apply injector if present (adds noise / faults)
            if ~isempty(obj.Injector)
                % Grab only the first output in case Injector.apply returns [y, inj]
                yOut = obj.Injector.apply(yOut, obj.dt);
            end

            obj.Out = yOut;
            y = yOut;
        end
    end
end