%% Injector.m
% Minimal noise + fault injection handle class.
% - Gaussian noise
% - Bias
% - Drift
% - Dropout windows
% - Spike events

classdef SensorInjectorSITL < handle
    properties
        % Noise
        Sigma (1,1) double = 1.5;        % [m] std dev
        EnableNoise (1,1) logical = true;

        % Bias/offset
        Bias (1,1) double = 0;           % [m]

        % Drift
        DriftRate (1,1) double = 0;      % [m/s]
        driftAccum (1,1) double = 0;

        % Dropout
        DropoutActive (1,1) logical = false;

        % Spikes
        SpikeActive (1,1) logical = false;
        SpikeMagnitude (1,1) double = 0; % [m]
    end

    methods
        function [y, meta] = apply(obj, x, dt)
            meta = struct("forceNoSignal", false, "forceNaN", false);

            % Drift integrates over time
            obj.driftAccum = obj.driftAccum + obj.DriftRate * dt;

            if obj.DropoutActive
                y = NaN;
                meta.forceNoSignal = true;
                return;
            end

            y = x + obj.Bias + obj.driftAccum;

            if obj.EnableNoise && isfinite(y)
                y = y + obj.Sigma * randn();
            end

            if obj.SpikeActive && isfinite(y)
                y = y + obj.SpikeMagnitude;
                % You can auto-clear spike after one sample by uncommenting:
                % obj.SpikeActive = false;
            end
        end
    end
end