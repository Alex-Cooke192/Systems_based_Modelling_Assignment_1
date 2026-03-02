%% runSensorCycle.m
% Simple cycle script to exercise all SITL sensors
% No injectors required (yet)

clear; clc;

%% Simulation parameters
Fs = 50;                 % master simulation rate
dt = 1/Fs;
Tsim = 5;                % seconds
t = 0:dt:Tsim;

%% Instantiate sensors (dumb versions)
altSensor   = AltitudeSensorSITL("Fs", Fs);
vsSensor    = VerticalSpeedSensorSITL("Fs", Fs);
asSensor    = AirspeedSensorSITL("Fs", Fs);
pitchSensor = PitchSensorSITL("Fs", Fs);
rollSensor  = RollSensorSITL("Fs", Fs);
tempSensor  = EngineTempSensorSITL("Fs", Fs);
oilSensor   = OilPressureSensorSITL("Fs", Fs);

%% Simple plant signals (just for demonstration)

% Altitude: slow climb with small oscillation
trueAlt = @(tt) 1000 + 2*tt + 20*sin(0.5*tt);

% Vertical speed = derivative of altitude approx
trueVS = @(tt) 2 + 10*cos(0.5*tt);

% Airspeed: oscillating
trueAS = @(tt) 60 + 5*sin(0.8*tt);

% Pitch & roll: small manoeuvres
truePitch = @(tt) 5*sin(0.6*tt);
trueRoll  = @(tt) 10*sin(0.4*tt);

% Engine temp: gradual warmup
trueTemp = @(tt) 80 + 0.5*tt;

% Oil pressure: steady
trueOil = @(tt) 400 + 10*sin(0.3*tt);

%% Header
fprintf("\nTime | Alt(m) | VS(m/s) | AS(m/s) | Pitch(deg) | Roll(deg) | Temp(C) | Oil(kPa)\n");
fprintf("---------------------------------------------------------------------------------------\n");

%% Main loop
for k = 1:length(t)

    tt = t(k);

    % Get true values
    alt  = trueAlt(tt);
    vs   = trueVS(tt);
    as   = trueAS(tt);
    pit  = truePitch(tt);
    rol  = trueRoll(tt);
    tmp  = trueTemp(tt);
    oil  = trueOil(tt);

    % Step sensors
    altOut = altSensor.step(alt);
    vsOut  = vsSensor.step(vs);
    asOut  = asSensor.step(as);
    pitOut = pitchSensor.step(pit);
    rolOut = rollSensor.step(rol);
    tmpOut = tempSensor.step(tmp);
    oilOut = oilSensor.step(oil);

    % Print every 0.2s to avoid flooding
    if mod(k, round(0.2/dt)) == 0
        fprintf("%4.1f | %7.2f | %7.2f | %7.2f | %10.2f | %9.2f | %7.2f | %8.2f\n", ...
            tt, altOut, vsOut, asOut, pitOut, rolOut, tmpOut, oilOut);
    end

end

fprintf("\nSimulation complete.\n");