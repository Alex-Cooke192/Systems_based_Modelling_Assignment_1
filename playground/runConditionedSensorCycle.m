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
Tsim = 20;               % seconds
t = 0:dt:Tsim;

%% Randomness / repeatability mode
MODE = "montecarlo";   % "repeatable" | "montecarlo"
runId = 1;             % only used for repeatable mode to vary scenario intentionally

%% Instantiate sensors (dumb versions)
altSensor   = AltitudeSensorSITL("Fs", Fs);
vsSensor    = VerticalSpeedSensorSITL("Fs", Fs);
asSensor    = AirspeedSensorSITL("Fs", Fs);
pitchSensor = PitchSensorSITL("Fs", Fs);
rollSensor  = RollSensorSITL("Fs", Fs);
tempSensor  = EngineTempSensorSITL("Fs", Fs);
oilSensor   = OilPressureSensorSITL("Fs", Fs);

%% Attach injectors (separate injector per sensor for independent faulting)
if MODE == "montecarlo"
    rng("shuffle");   % ensure randi() differs each run
end

enableFaults = true;
if enableFaults
    altSensor.Injector   = SimpleInjector("Seed", pickSeed(MODE,runId,1), "NoiseSigma",0.2, "FaultRatePerSecond",0.2, "MinFaultDuration",0.2, ...
                                          "MaxFaultDuration",0.6,"BiasMagnitude",2, "DriftRateMagnitude",0.2, "SpikeMagnitude",20, "W_Dropout",1);
    vsSensor.Injector    = SimpleInjector("Seed", pickSeed(MODE,runId,2), "NoiseSigma",0.2, "FaultRatePerSecond",0.2, "MinFaultDuration",0.2, ...
                                           "MaxFaultDuration",0.6,"BiasMagnitude",1, "DriftRateMagnitude",0.1, "SpikeMagnitude",10, "W_Dropout",1);
    asSensor.Injector    = SimpleInjector("Seed", pickSeed(MODE,runId,3), "NoiseSigma",0.2, "FaultRatePerSecond",0.2, "MinFaultDuration",0.2, ...
                                          "MaxFaultDuration",0.6,"BiasMagnitude",1, "DriftRateMagnitude",0.1, "SpikeMagnitude",5,  "W_Dropout",1);
    pitchSensor.Injector = SimpleInjector("Seed", pickSeed(MODE,runId,4), "NoiseSigma",0.2, "FaultRatePerSecond",0.2, "MinFaultDuration",0.2, ...
                                          "MaxFaultDuration",0.6,"BiasMagnitude",0.5,"DriftRateMagnitude",0.05,"SpikeMagnitude",5,  "W_Dropout",1);
    rollSensor.Injector  = SimpleInjector("Seed", pickSeed(MODE,runId,5), "NoiseSigma",0.2, "FaultRatePerSecond",0.2, "MinFaultDuration",0.2, ...
                                          "MaxFaultDuration",0.6,"BiasMagnitude",1, "DriftRateMagnitude",0.05,"SpikeMagnitude",8,  "W_Dropout",1);
    tempSensor.Injector  = SimpleInjector("Seed", pickSeed(MODE,runId,6), "NoiseSigma",0.2, "FaultRatePerSecond",0.2, "MinFaultDuration",0.2, ...
                                          "MaxFaultDuration",0.6,"BiasMagnitude",2, "DriftRateMagnitude",0.2, "SpikeMagnitude",15, "W_Dropout",1);
    oilSensor.Injector   = SimpleInjector("Seed", pickSeed(MODE,runId,7), "NoiseSigma",0.2, "FaultRatePerSecond",0.10, "MinFaultDuration",0.2, ...
                                          "MaxFaultDuration",0.6,"BiasMagnitude",5, "DriftRateMagnitude",0.5, "SpikeMagnitude",50, "W_Dropout",1);
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

%% Instantiate Orchestrator Object
orchestrator = SensorOrchestrator("Fs", Fs); 

%% Create logger & attach as property to orchestrator object
logger = Logger(); 
orchestrator.logger = logger; 

fprintf("\nOrchestrator Outputs\n")

for k = 1:length(t)
    tt = t(k); 
    % Get all current values
    altT = trueAlt(tt);
    vsT  = trueVS(tt);
    asT  = trueAS(tt);
    pitT = truePitch(tt);
    rolT = trueRoll(tt);
    tmpT = trueTemp(tt);
    oilT = trueOil(tt);

    % Step sensors (raw measured outputs + injector meta)
    [altMeas, altMeta] = altSensor.step(altT);
    [vsMeas,  vsMeta ] = vsSensor.step(vsT);
    [asMeas,  asMeta ] = asSensor.step(asT);
    [pitMeas, pitMeta] = pitchSensor.step(pitT);
    [rolMeas, rolMeta] = rollSensor.step(rolT);
    [tmpMeas, tmpMeta] = tempSensor.step(tmpT);
    [oilMeas, oilMeta] = oilSensor.step(oilT);

    % Run monitors (conditioning + health)
    [altC, altS] = altMon.step(altMeas);
    [vsC,  vsS ] = vsMon.step(vsMeas);
    [asC,  asS ] = asMon.step(asMeas);
    [pitC, pitS] = pitchMon.step(pitMeas);
    [rolC, rolS] = rollMon.step(rolMeas);
    [tmpC, tmpS] = tempMon.step(tmpMeas);
    [oilC, oilS] = oilMon.step(oilMeas);

    % Decide what to print as "fault type" for each sensor (only show when S/F)
    altF = faultLabelIfSF(altS, altMeta);
    vsF  = faultLabelIfSF(vsS,  vsMeta);
    asF  = faultLabelIfSF(asS,  asMeta);
    pitF = faultLabelIfSF(pitS, pitMeta);
    rolF = faultLabelIfSF(rolS, rolMeta);
    tmpF = faultLabelIfSF(tmpS, tmpMeta);
    oilF = faultLabelIfSF(oilS, oilMeta);

    % Plug into orchestrator and step
    states = struct(...
        "AltitudeSensor",altS,...
        "AirspeedSensor",asS,...
        "VerticalSpeedSensor",vsS, ...
        "PitchSensor",pitS,...
        "RollSensor",rolS,...
        "TemperatureSensor",tmpS,...
        "PressureSensor",oilS);
    values = struct(...
        "Altitude",altC,...
        "VerticalSpeed",vsC);
    

    [state, logMsg, diagnostics] = orchestrator.step(states, values, tt);
    
    % 1) Overall system state string comes from orchestrator
    sysStateStr = state;
    
    % 2) Map system state string -> sysS ('N','S','F')
    switch upper(string(sysStateStr))
        case "NORMAL"
            sysS = 'N';
        case "WARN"
            sysS = 'S';
        case {"FAIL","FAILED","FAULT"}
            sysS = 'F';
        otherwise
            sysS = 'N';
    end
    
    % 3) Create Sysmeta.label from sensor states (simple cause selection)
    Sysmeta = struct("label","");
    
    names  = ["ALT","VS","AS","PIT","ROL","TMP","OIL"];
    sStates = [altS,  vsS,  asS,  pitS,  rolS,  tmpS,  oilS];
    
    % NOTE: your monitor outputs are strings like "SUSPECT"/"FAILED"/"OK"
    idxF = find(sStates == "FAILED",  1, "first");
    idxS = find(sStates == "SUSPECT", 1, "first");
    
    if ~isempty(idxF)
        Sysmeta.label = "SensorFailed:" + names(idxF);
    elseif ~isempty(idxS)
        Sysmeta.label = "SensorSuspect:" + names(idxS);
    else
        Sysmeta.label = "";
    end
    
    % 4) Overall label only when WARN/FAIL
    sysF = OverallFaultLabelIfSF(sysS, Sysmeta);
    
    fprintf("System: %s (%c)  Cause: %s\n", sysStateStr, sysS, sysF);
    
        fprintf("Current State: %s \n", state)
        fprintf("Log Message: %s \n", logMsg)
        disp(diagnostics)
    end 

fprintf("\nSimulation complete.\n");

function s = pickSeed(MODE, runId, sensorIndex)
% pickSeed: returns a seed for a given sensor
% - repeatable: deterministic but can be varied with runId
% - montecarlo: different each run, but still independent per sensor

    switch MODE
        case "repeatable"
            s = 1000 + runId*100 + sensorIndex;   % deterministic & easy to cite
        case "montecarlo"
            s = randi(1e9);                       % new each run
        otherwise
            error("Unknown MODE: %s", MODE);
    end
end

function label = faultLabelIfSF(stateStr, meta)
% Prints injector fault type only when the monitor says SUSPECT/FAILED.
% Otherwise prints "-" to keep the table readable.
    if stateStr == "SUSPECT" || stateStr == "FAILED"
        if isstruct(meta) && isfield(meta,"faultActive") && isfield(meta,"faultType") && meta.faultActive
            label = char(meta.faultType);
        else
            % SUSPECT/FAILED but injector says no fault active -> likely noise/thresholding
            label = "NONE?";
        end
    else
        label = "-";
    end
end

function lab = OverallFaultLabelIfSF(sysS, Sysmeta)
    if sysS=='S' || sysS=='F'
        lab = Sysmeta.label;
    else
        lab = "";
    end
end