%% RunConditionedSensorCycle.m
% Cycles all SITL sensors, then runs each through its monitor (conditioning + health SM),
% then prints conditioned outputs (and optional health states). 
% 
% Build for 7 sensors in simulation, along with corresponding sensors &
% simpleInjector class

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

%% Attach injectors (separate injector per sensor for independent faulting)
enableFaults = true;
if enableFaults
    altSensor.Injector   = SimpleInjector("Seed",1, "NoiseSigma",0.05, "FaultRatePerSecond",0.15, "FaultDurationSeconds",0.25, ...
                                          "BiasMagnitude",2, "DriftRateMagnitude",0.2, "SpikeMagnitude",20, "W_Dropout",1);
    vsSensor.Injector    = SimpleInjector("Seed",2, "NoiseSigma",0.05, "FaultRatePerSecond",0.15, "FaultDurationSeconds",0.25, ...
                                          "BiasMagnitude",1, "DriftRateMagnitude",0.1, "SpikeMagnitude",10, "W_Dropout",1);
    asSensor.Injector    = SimpleInjector("Seed",3, "NoiseSigma",0.05, "FaultRatePerSecond",0.15, "FaultDurationSeconds",0.25, ...
                                          "BiasMagnitude",1, "DriftRateMagnitude",0.1, "SpikeMagnitude",5,  "W_Dropout",1);
    pitchSensor.Injector = SimpleInjector("Seed",4, "NoiseSigma",0.05, "FaultRatePerSecond",0.15, "FaultDurationSeconds",0.25, ...
                                          "BiasMagnitude",0.5,"DriftRateMagnitude",0.05,"SpikeMagnitude",5,  "W_Dropout",1);
    rollSensor.Injector  = SimpleInjector("Seed",5, "NoiseSigma",0.05, "FaultRatePerSecond",0.15, "FaultDurationSeconds",0.25, ...
                                          "BiasMagnitude",1, "DriftRateMagnitude",0.05,"SpikeMagnitude",8,  "W_Dropout",1);
    tempSensor.Injector  = SimpleInjector("Seed",6, "NoiseSigma",0.05, "FaultRatePerSecond",0.10, "FaultDurationSeconds",0.35, ...
                                          "BiasMagnitude",2, "DriftRateMagnitude",0.2, "SpikeMagnitude",15, "W_Dropout",1);
    oilSensor.Injector   = SimpleInjector("Seed",7, "NoiseSigma",0.05, "FaultRatePerSecond",0.10, "FaultDurationSeconds",0.35, ...
                                          "BiasMagnitude",5, "DriftRateMagnitude",0.5, "SpikeMagnitude",50, "W_Dropout",1);
end

%% Instantiate monitors (conditioning + health state machines)
altMon   = AltitudeMonitor("Fs", Fs);
vsMon    = VerticalSpeedMonitor("Fs", Fs);
asMon    = AirspeedMonitor("Fs", Fs);
pitchMon = PitchMonitor("Fs", Fs);
rollMon  = RollMonitor("Fs", Fs);
tempMon  = EngineTempMonitor("Fs", Fs);
oilMon   = OilPressureMonitor("Fs", Fs);

%% Planted signals (just for demonstration)
trueAlt   = @(tt) 1000 + 2*tt + 20*sin(0.5*tt);
trueVS    = @(tt) 2 + 10*cos(0.5*tt);
trueAS    = @(tt) 60 + 5*sin(0.8*tt);
truePitch = @(tt) 5*sin(0.6*tt);
trueRoll  = @(tt) 10*sin(0.4*tt);
trueTemp  = @(tt) 80 + 0.5*tt;
trueOil   = @(tt) 400 + 10*sin(0.3*tt);

%% Header (conditioned outputs + state codes)
fprintf("\nConditioned Sensor Outputs\n");
fprintf("Time | Alt(m)  AltSt | VS(m/s)  VSSt | AS(m/s)  ASSt | Pitch(deg) PSt | Roll(deg) RSt | Temp(C)  TSt | Oil(kPa)  OSt\n");
fprintf("------------------------------------------------------------------------------------------------------------------------\n");

%% Helper to print state of each sensor
stateCode = @(s) char( ...
    (s=="OK")*"O" + (s=="SUSPECT")*"S" + (s=="FAILED")*"F" );

%% Main loop
printEvery = round(0.2/dt);

for k = 1:length(t)
    tt = t(k);

    % True values
    altT = trueAlt(tt);
    vsT  = trueVS(tt);
    asT  = trueAS(tt);
    pitT = truePitch(tt);
    rolT = trueRoll(tt);
    tmpT = trueTemp(tt);
    oilT = trueOil(tt);

    % Step sensors (raw measured outputs)
    altMeas = altSensor.step(altT);
    vsMeas  = vsSensor.step(vsT);
    asMeas  = asSensor.step(asT);
    pitMeas = pitchSensor.step(pitT);
    rolMeas = rollSensor.step(rolT);
    tmpMeas = tempSensor.step(tmpT);
    oilMeas = oilSensor.step(oilT);

    % Run monitors (conditioning + health)
    [altC, altS] = altMon.step(altMeas);
    [vsC,  vsS ] = vsMon.step(vsMeas);
    [asC,  asS ] = asMon.step(asMeas);
    [pitC, pitS] = pitchMon.step(pitMeas);
    [rolC, rolS] = rollMon.step(rolMeas);
    [tmpC, tmpS] = tempMon.step(tmpMeas);
    [oilC, oilS] = oilMon.step(oilMeas);

    % Print
    if mod(k, printEvery) == 0
        fprintf("%4.1f | %7.2f   %1s  | %7.2f   %1s  | %7.2f   %1s  | %9.2f   %1s  | %8.2f   %1s  | %7.2f   %1s  | %8.2f   %1s\n", ...
            tt, altC, stateCode(altS), ...
                vsC,  stateCode(vsS),  ...
                asC,  stateCode(asS),  ...
                pitC, stateCode(pitS), ...
                rolC, stateCode(rolS), ...
                tmpC, stateCode(tmpS), ...
                oilC, stateCode(oilS));
    end
end

fprintf("\nSimulation complete.\n");