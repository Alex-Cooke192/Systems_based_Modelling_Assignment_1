%% runBehaviouralScenario.m
clear; clc;

scenarioId = "BV-4c";   % choose: BV-1, BV-2, BV-3, BV-4a, BV-4b, BV-4c, BV-4d, BV-5

%% Simulation parameters
Fs = 10;
dt = 1/Fs;
Tsim = 20;
t = 0:dt:Tsim;

%% Instantiate sensors
altSensor   = AltitudeSensorSITL("Fs", Fs);
vsSensor    = VerticalSpeedSensorSITL("Fs", Fs);
asSensor    = AirspeedSensorSITL("Fs", Fs);
pitchSensor = PitchSensorSITL("Fs", Fs);
rollSensor  = RollSensorSITL("Fs", Fs);
tempSensor  = EngineTempSensorSITL("Fs", Fs);
oilSensor   = OilPressureSensorSITL("Fs", Fs);

%% Default: no faults
altSensor.Injector   = DeterministicInjector();
vsSensor.Injector    = DeterministicInjector();
asSensor.Injector    = DeterministicInjector();
pitchSensor.Injector = DeterministicInjector();
rollSensor.Injector  = DeterministicInjector();
tempSensor.Injector  = DeterministicInjector();
oilSensor.Injector   = DeterministicInjector();

%% Apply scenario-specific scripted fault
%% Apply scenario-specific scripted fault
switch scenarioId
    case "BV-1"
        % Nominal: no injected faults

    case "BV-2"
        % Safety-critical sensor invalid/out-of-range
        altSensor.Injector = DeterministicInjector( ...
            "Enabled", true, ...
            "FaultType", "DROPOUT", ...
            "FaultStartTime", 5.0, ...
            "FaultDuration", 0.8, ...
            "DropoutAsNaN", true);

    case "BV-3"
        % Non-safety-critical sensor invalid/out-of-range
        tempSensor.Injector = DeterministicInjector( ...
            "Enabled", true, ...
            "FaultType", "DROPOUT", ...
            "FaultStartTime", 5.0, ...
            "FaultDuration", 0.8, ...
            "DropoutAsNaN", true);

    case "BV-4a"
        % Stuck-at fault on Airspeed
        asSensor.Injector = DeterministicInjector( ...
            "Enabled", true, ...
            "FaultType", "STUCK", ...
            "FaultStartTime", 5.0, ...
            "FaultDuration", 1.2);

    case "BV-4b"
        % Bias fault on Pitch
        pitchSensor.Injector = DeterministicInjector( ...
            "Enabled", true, ...
            "FaultType", "BIAS", ...
            "FaultStartTime", 5.0, ...
            "FaultDuration", 1.2, ...
            "BiasMagnitude", 5.0);

    case "BV-4c"
        % Drift fault on Roll
        rollSensor.Injector = DeterministicInjector( ...
            "Enabled", true, ...
            "FaultType", "DRIFT", ...
            "FaultStartTime", 5.0, ...
            "FaultDuration", 1.5, ...
            "DriftRateMagnitude", 3.0);

    case "BV-4d"
        % Dropout fault on Oil Pressure
        oilSensor.Injector = DeterministicInjector( ...
            "Enabled", true, ...
            "FaultType", "DROPOUT", ...
            "FaultStartTime", 5.0, ...
            "FaultDuration", 0.8, ...
            "DropoutAsNaN", true);

    case "BV-5"
        % Redundancy mismatch: bias VS so it disagrees with d(alt)/dt
        vsSensor.Injector = DeterministicInjector( ...
            "Enabled", true, ...
            "FaultType", "BIAS", ...
            "FaultStartTime", 5.0, ...
            "FaultDuration", 1.5, ...
            "BiasMagnitude", 7.0);

    otherwise
        error("Unknown scenarioId: %s", scenarioId);
end

%% Instantiate monitors
altMon   = AltitudeMonitor("Fs", Fs);
vsMon    = VerticalSpeedMonitor("Fs", Fs);
asMon    = AirspeedMonitor("Fs", Fs);
pitchMon = PitchMonitor("Fs", Fs);
rollMon  = RollMonitor("Fs", Fs);
tempMon  = EngineTempMonitor("Fs", Fs);
oilMon   = OilPressureMonitor("Fs", Fs);

%% Truth signals
trueAlt   = @(tt) 1000 + 2*tt + 20*sin(0.5*tt);
trueVS    = @(tt) 2 + 10*cos(0.5*tt);
trueAS    = @(tt) 60 + 5*sin(0.8*tt);
truePitch = @(tt) 5*sin(0.6*tt);
trueRoll  = @(tt) 10*sin(0.4*tt);
trueTemp  = @(tt) 80 + 0.5*tt;
trueOil   = @(tt) 400 + 10*sin(0.3*tt);

%% Orchestrator + logger
orchestrator = SensorOrchestrator("Fs", Fs);
logger = Logger();
orchestrator.logger = logger;

%% Evidence storage
sensorStates = strings(length(t), 7);
systemStates = strings(length(t), 1);
classifiedStates = zeros(length(t), 1);   % for BV-4 scenarios only

%% Redundancy Mismatch storage
altC_hist = nan(length(t),1);
vsC_hist  = nan(length(t),1);
sysStateNum = nan(length(t),1);

for k = 1:length(t)
    tt = t(k);

    altT = trueAlt(tt);
    vsT  = trueVS(tt);
    asT  = trueAS(tt);
    pitT = truePitch(tt);
    rolT = trueRoll(tt);
    tmpT = trueTemp(tt);
    oilT = trueOil(tt);

    [altMeas, altMeta] = altSensor.step(altT);
    [vsMeas,  vsMeta ] = vsSensor.step(vsT);
    [asMeas,  asMeta ] = asSensor.step(asT);
    [pitMeas, pitMeta] = pitchSensor.step(pitT);
    [rolMeas, rolMeta] = rollSensor.step(rolT);
    [tmpMeas, tmpMeta] = tempSensor.step(tmpT);
    [oilMeas, oilMeta] = oilSensor.step(oilT);

    [altC, altS] = altMon.step(altMeas);
    [vsC,  vsS ] = vsMon.step(vsMeas);
    [asC,  asS ] = asMon.step(asMeas);
    [pitC, pitS] = pitchMon.step(pitMeas);
    [rolC, rolS] = rollMon.step(rolMeas);
    [tmpC, tmpS] = tempMon.step(tmpMeas);
    [oilC, oilS] = oilMon.step(oilMeas);

    altC_hist(k) = altC;
    vsC_hist(k)  = vsC;

    states = struct( ...
        "AltitudeSensor", altS, ...
        "AirspeedSensor", asS, ...
        "VerticalSpeedSensor", vsS, ...
        "PitchSensor", pitS, ...
        "RollSensor", rolS, ...
        "TemperatureSensor", tmpS, ...
        "PressureSensor", oilS);

    values = struct( ...
        "Altitude", altC, ...
        "VerticalSpeed", vsC);

    [state, logMsg, diagnostics] = orchestrator.step(states, values, tt);

    switch state
        case "NORMAL"
            sysStateNum(k) = 0;
        case "WARN"
            sysStateNum(k) = 1;
        case "FAULT"
            sysStateNum(k) = 2;
    end

    sensorStates(k,:) = [altS, asS, vsS, pitS, rolS, tmpS, oilS];
    systemStates(k) = state;

    % Store ground-truth injected fault class for BV-4 scenarios
    if scenarioId == "BV-4a"
        classifiedStates(k) = FaultClassifier(asMeta);
    elseif scenarioId == "BV-4b"
        classifiedStates(k) = FaultClassifier(pitMeta);
    elseif scenarioId == "BV-4c"
        classifiedStates(k) = FaultClassifier(rolMeta);
    elseif scenarioId == "BV-4d"
        classifiedStates(k) = FaultClassifier(oilMeta);
    end

    fprintf("t=%.2f  SYS=%s  ALT=%s  VS=%s  AS=%s  PIT=%s  ROL=%s  TMP=%s  OIL=%s\n", ...
        tt, state, altS, vsS, asS, pitS, rolS, tmpS, oilS);
end

%% Calculate the rate of change of the altitude
altSlope_hist = nan(length(t),1);

for k = 2:length(t)
    if ~isnan(altC_hist(k)) && ~isnan(altC_hist(k-1))
        altSlope_hist(k) = (altC_hist(k) - altC_hist(k-1)) / dt;
    end
end

if startsWith(scenarioId, "BV-")
    %% Convert sensor states to numeric values for plotting
    stateMap = containers.Map(["OK","SUSPECT","FAILED"], [0 1 2]);
    numStates = zeros(length(t), 7);
    
    for i = 1:length(t)
        for j = 1:7
            numStates(i,j) = stateMap(sensorStates(i,j));
        end
    end
    
    %% Plot sensor health states over time
    sensorNames = ["Altitude","Airspeed","VertSpeed","Pitch","Roll","Temp","Oil"];
    
    figure
    
    subplot(2,1,1)
    hold on
    for i = 1:7
        offset = (i-1)*3;
        stairs(t, numStates(:,i) + offset, 'LineWidth', 2)
    end
    
    % Create tick labels
    stateLabels = ["OK","SUSPECT","FAILED"];
    yticks(0:1:(7*3-1))
    
    labels = strings(21,1);
    idx = 1;
    
    for s = 1:7
        for st = 1:3
            labels(idx) = sensorNames(s) + " - " + stateLabels(st);
            idx = idx + 1;
        end
    end
    
    yticklabels(labels)
    
    if scenarioId == "BV-2" || scenarioId == "BV-3" || scenarioId == "BV-4a" || ...
       scenarioId == "BV-4b" || scenarioId == "BV-4c" || scenarioId == "BV-4d" || ...
       scenarioId == "BV-5"
        xline(5.0, '--r', 'Fault injected')
    end
    
    xlabel("Time (s)")
    ylabel("Sensor State")
    title(sprintf("Sensor Health States During Scenario %s", scenarioId))
    grid on
    %% Overall System State Graph

    subplot(2,1,2)
    % Plot OVERALL State
    stairs(t, sysStateNum, 'LineWidth', 2)

    % add fault injected marker
    xline(5.0, '--r', 'Fault injected')

    % Get states
    yticks([0 1 2])
    yticklabels(["NORMAL", "WARN", "FAULT"])

    % Add labels to diagram
    xlabel("Time (s)")
    ylabel("System State")
    title("Overall System State During " + scenarioId)

    grid on
end

%% Plot detected sensor state for BV-4 scenarios
if scenarioId == "BV-4a" || scenarioId == "BV-4b" || scenarioId == "BV-4c" || scenarioId == "BV-4d"

    detectedStateNames = ["OK", "SUSPECT", "FAILED"];
    detectedStateNum = nan(length(t), 1);

    % Select affected sensor column
    switch scenarioId
        case "BV-4a"
            thisSensorStates = sensorStates(:,2);   % Airspeed
            sensorLabel = "Airspeed";
            faultName = "Stuck-at"; 
        case "BV-4b"
            thisSensorStates = sensorStates(:,4);   % Pitch
            sensorLabel = "Pitch";
            faultName = "Bias"; 
        case "BV-4c"
            thisSensorStates = sensorStates(:,5);   % Roll
            sensorLabel = "Roll";
            faultName = "Drift"; 
        case "BV-4d"
            thisSensorStates = sensorStates(:,7);   % Oil Pressure
            sensorLabel = "Oil Pressure";
            faultName = "Dropout"; 
    end

    % Convert state strings to numeric values for plotting
    for k = 1:length(t)
        switch string(thisSensorStates(k))
            case "OK"
                detectedStateNum(k) = 0;
            case "SUSPECT"
                detectedStateNum(k) = 1;
            case "FAILED"
                detectedStateNum(k) = 2;
        end
    end

    figure
    stairs(t, detectedStateNum, 'LineWidth', 2)
    xline(5.0, '--r', faultName + 'Fault Injected')

    yticks(0:2)
    yticklabels(detectedStateNames)

    ylabel(sensorLabel + " Monitor State")
    xlabel("Time (s)")
    title(sprintf("Detected Sensor State During Scenario %s and fault type %s", scenarioId, faultName))
    grid on
end
disp("Scenario complete.");

if scenarioId == "BV-5"

    figure

    subplot(2,1,1)
    plot(t, vsC_hist, 'LineWidth', 2)
    hold on
    plot(t, altSlope_hist, 'LineWidth', 2)
    xline(5.0, '--r', 'Fault injected')
    xlabel("Time (s)")
    ylabel("Rate")
    title("Redundancy Mismatch Evidence")
    legend("Vertical Speed", "d(Altitude)/dt", 'Location', 'best')
    grid on

    subplot(2,1,2)
    stairs(t, sysStateNum, 'LineWidth', 2)
    xline(5.0, '--r', 'Fault injected')
    yticks([0 1 2])
    yticklabels(["NORMAL","WARN","FAULT"])
    xlabel("Time (s)")
    ylabel("System State")
    title("Orchestrator State")
    grid on

end

%% Local helper function
function classId = FaultClassifier(meta)
% Converts injector metadata into a numeric fault-class label.
%
% Output mapping:
%   0 = Normal
%   1 = Stuck-at
%   2 = Bias
%   3 = Drift
%   4 = Spike
%   5 = Dropout

    classId = 0;  % default = Normal

    if ~isstruct(meta)
        return;
    end

    if ~isfield(meta, "faultActive") || ~isfield(meta, "faultType")
        return;
    end

    if ~meta.faultActive
        classId = 0;
        return;
    end

    switch upper(string(meta.faultType))
        case "STUCK"
            classId = 1;
        case "BIAS"
            classId = 2;
        case "DRIFT"
            classId = 3;
        case "SPIKE"
            classId = 4;
        case "DROPOUT"
            classId = 5;
        otherwise
            classId = 0;
    end
end
