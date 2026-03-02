%% VerticalSpeedSensorSITL.m
% Dumb SITL vertical speed sensor emulator:
% - Takes an input value each step()
% - Optionally applies an Injector (noise/faults)
% - Outputs the noisy value
% - No filtering, no rate limiting, no validity checking, no health state machine

classdef VerticalSpeedSensorSITL < handle
    properties
        Fs (1,1) double = 50;     % Sample rate [Hz]
        dt (1,1) double = 0.02;   % Sample period [s]

        % TODO: external injector (noise + faults)
        % Handle object with method:
        %   [y, inj] = apply(x, dt)
        Injector = [];
    end

    properties (SetAccess = private)
        Raw (1,1) double = NaN;   % last input value received
        Out (1,1) double = NaN;   % last output value after injector
    end

    properties (Access = private)
        dtWasExplicitlySet (1,1) logical = false;
    end

    methods
        function obj = VerticalSpeedSensorSITL(varargin)
            % Name-value init
            for k = 1:2:numel(varargin)
                name = varargin{k};
                val  = varargin{k+1};

                if strcmpi(name, "dt")
                    obj.dtWasExplicitlySet = true;
                end

                obj.(name) = val;
            end

            % If dt wasn't explicitly set, derive it from Fs
            if ~obj.dtWasExplicitlySet
                obj.dt = 1/obj.Fs;
            end
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

        function yOut = step(obj, trueVS)
            % step() takes the "true" vertical speed and returns a noisy measurement.

            obj.Raw = trueVS;

            y = trueVS;

            % Apply injector if present (adds noise / faults)
            if ~isempty(obj.Injector)
                % Injector is responsible for "how" noise is applied.
                % We ignore any extra metadata it returns.
                y = obj.Injector.apply(y, obj.dt);
                % If Injector.apply returns [y, inj], MATLAB will put the
                % whole first output into y, which is what we want.
            end

            obj.Out = y;
            yOut = y;
        end
    end
end