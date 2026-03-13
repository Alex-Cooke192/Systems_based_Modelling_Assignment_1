%% runBehaviouralScenario.m
clear; clc;

scenarioId = "MCV-3";   % choose: MCV-1, MCV-2, MCV-3

%% Simulation parameters
N = 1000;                 % Number of trials
Fs = 100;
dt = 1/Fs;
Tsim = 20;
t = 0:dt:Tsim;

%% Requirement thresholds
req = struct();

% Per-run storage
warnTimestepsPerRun  = zeros(N,1);
faultTimestepsPerRun = zeros(N,1);
warnEntriesPerRun    = zeros(N,1);
faultEntriesPerRun   = zeros(N,1);

% MCV-1 robustness requirements
req.MCV1.maxWarnTimestepsPerRun  = 0;
req.MCV1.maxFaultTimestepsPerRun = 0;
req.MCV1.maxWarnEntriesPerRun    = 0;
req.MCV1.maxFaultEntriesPerRun   = 0;

% MCV-2 fault-detection requirements
req.MCV2.maxDetectionDelay = 0.01;        % seconds
req.MCV2.minDetectionProbability = 95;   % percent

% MCV-3 redundancy-mismatch requirements
req.MCV3.minWarnDetectionProbability  = 95;   % percent
req.MCV3.maxWarnDetectionDelay        = 0.5;  % seconds

req.MCV3.minFaultEscalationProbability = 95;  % percent
req.MCV3.maxFaultEscalationDelay       = 1.5; % seconds

% Run-level outcome storage
warnOccured = zeros(N,1);
faultOccured = zeros(N,1);

warnEvents = 0;
faultEvents = 0;

warnTimesteps = zeros(N, length(t));

% Run-level detection results for MCV-2
detectedRuns       = zeros(N,1);
detectionDelayRuns = nan(N,1);
faultTypeRuns      = strings(N,1);
faultedSensorRuns  = strings(N,1);
faultStartRuns     = nan(N,1);

% Run-level detection results for MCV-3
mismatchStartRuns        = nan(N,1);
mismatchDurationRuns     = nan(N,1);
warnDetectedRuns_MCV3    = zeros(N,1);
faultDetectedRuns_MCV3   = zeros(N,1);
warnDelayRuns_MCV3       = nan(N,1);
faultDelayRuns_MCV3      = nan(N,1);
mismatchMagnitudeRuns    = nan(N,1);
mismatchModeRuns         = strings(N,1);   % "VS_BIAS", "ALT_BIAS", "BOTH"

%% Monte Carlo loop
for run = 1:N
    warnPresent = zeros(1, length(t));
    faultPresent = zeros(1, length(t));

    thisRunWarnEntries = 0;
    thisRunFaultEntries = 0;

    %% Instantiate sensors
    altSensor   = AltitudeSensorSITL("Fs", Fs);
    vsSensor    = VerticalSpeedSensorSITL("Fs", Fs);
    asSensor    = AirspeedSensorSITL("Fs", Fs);
    pitchSensor = PitchSensorSITL("Fs", Fs);
    rollSensor  = RollSensorSITL("Fs", Fs);
    tempSensor  = EngineTempSensorSITL("Fs", Fs);
    oilSensor   = OilPressureSensorSITL("Fs", Fs);

    %% Default injectors
    switch scenarioId
        case "MCV-1"
            altSensor.Injector   = SimpleInjector();
            vsSensor.Injector    = SimpleInjector();
            asSensor.Injector    = SimpleInjector();
            pitchSensor.Injector = SimpleInjector();
            rollSensor.Injector  = SimpleInjector();
            tempSensor.Injector  = SimpleInjector();
            oilSensor.Injector   = SimpleInjector();

        case "MCV-2"
            altSensor.Injector   = DeterministicInjector();
            vsSensor.Injector    = DeterministicInjector();
            asSensor.Injector    = DeterministicInjector();
            pitchSensor.Injector = DeterministicInjector();
            rollSensor.Injector  = DeterministicInjector();
            tempSensor.Injector  = DeterministicInjector();
            oilSensor.Injector   = DeterministicInjector();

        case "MCV-3"
            % placeholder
    end

    %% Apply scenario-specific configuration
    switch scenarioId
        case "MCV-1"
            altSensor.Injector = SimpleInjector("NoiseSigma", 0.3, "FaultRatePerSecond", 0.0);
            vsSensor.Injector = SimpleInjector("NoiseSigma", 0.1, "FaultRatePerSecond", 0.0);
            asSensor.Injector = SimpleInjector("NoiseSigma", 0.1, "FaultRatePerSecond", 0.0);
            pitchSensor.Injector = SimpleInjector("NoiseSigma", 0.3, "FaultRatePerSecond", 0.0);
            rollSensor.Injector = SimpleInjector("NoiseSigma", 0.3, "FaultRatePerSecond", 0.0);
            tempSensor.Injector = SimpleInjector("NoiseSigma", 0.5, "FaultRatePerSecond", 0.0);
            oilSensor.Injector = SimpleInjector("NoiseSigma", 0.2, "FaultRatePerSecond", 0.0);

        case "MCV-2"
            % Choose one fault type per run
            failureClasses = ["BIAS", "DRIFT", "STUCK", "DROPOUT"];
            idx = randi(length(failureClasses));
            FaultType = failureClasses(idx);

            % Choose one target sensor per run
            sensorNames = ["ALT","VS","AS","PIT","ROL","TMP","OIL"];
            sensorIdx = randi(length(sensorNames));
            targetSensor = sensorNames(sensorIdx);

            % Store for later analysis
            faultTypeRuns(run) = FaultType;
            faultedSensorRuns(run) = targetSensor;

            % Random fault start time
            faultStart = 5.0 + 5.0*rand();
            faultStartRuns(run) = faultStart;

            commonArgs = { ...
                "NoiseSigma", 0.3, ...
                "Enabled", true, ...
                "FaultType", FaultType, ...
                "FaultStartTime", faultStart, ...
                "FaultDuration", 2.0 ...
            };

            specificArgs = {};
            switch FaultType
                case "BIAS"
                    specificArgs = {"BiasMagnitude", 1 + 4*rand()};
                case "DRIFT"
                    specificArgs = {"DriftRateMagnitude", 0.5 + 2*rand()};
                case "DROPOUT"
                    specificArgs = {"DropoutAsNaN", true};
                case "STUCK"
                    specificArgs = {};
            end

            % Nominal injectors first
            altSensor.Injector   = DeterministicInjector("NoiseSigma", 0.3);
            vsSensor.Injector    = DeterministicInjector("NoiseSigma", 0.1);
            asSensor.Injector    = DeterministicInjector("NoiseSigma", 0.1);
            pitchSensor.Injector = DeterministicInjector("NoiseSigma", 0.3);
            rollSensor.Injector  = DeterministicInjector("NoiseSigma", 0.3);
            tempSensor.Injector  = DeterministicInjector("NoiseSigma", 0.5);
            oilSensor.Injector   = DeterministicInjector("NoiseSigma", 0.2);

            % Apply fault only to selected sensor
            switch targetSensor
                case "ALT"
                    altSensor.Injector = DeterministicInjector(commonArgs{:}, specificArgs{:});
                case "VS"
                    vsSensor.Injector = DeterministicInjector(commonArgs{:}, specificArgs{:});
                case "AS"
                    asSensor.Injector = DeterministicInjector(commonArgs{:}, specificArgs{:});
                case "PIT"
                    pitchSensor.Injector = DeterministicInjector(commonArgs{:}, specificArgs{:});
                case "ROL"
                    rollSensor.Injector = DeterministicInjector(commonArgs{:}, specificArgs{:});
                case "TMP"
                    tempSensor.Injector = DeterministicInjector(commonArgs{:}, specificArgs{:});
                case "OIL"
                    oilSensor.Injector = DeterministicInjector(commonArgs{:}, specificArgs{:});
            end

            detectedThisRun = false;
            detectionTime = NaN;


        case "MCV-3"
            % Randomised mismatch onset and persistence
            mismatchStart = 5.0 + 5.0*rand();      % 5 to 10 s
            mismatchDuration = 1.0 + 3.0*rand();   % 1 to 4 s

            mismatchStartRuns(run) = mismatchStart;
            mismatchDurationRuns(run) = mismatchDuration;

            % Choose how mismatch is created
            mismatchModes = ["VS_BIAS", "ALT_BIAS", "BOTH"];
            mmIdx = randi(length(mismatchModes));
            mismatchMode = mismatchModes(mmIdx);
            mismatchModeRuns(run) = mismatchMode;

            % Mismatch magnitude
            % Keep this large enough to trigger redundancy logic under noise
            mismatchMag = 3 + 5*rand();   % e.g. 3 to 8 units
            mismatchMagnitudeRuns(run) = mismatchMag;

            % Nominal injectors for all sensors
            altSensor.Injector   = DeterministicInjector("NoiseSigma", 0.3);
            vsSensor.Injector    = DeterministicInjector("NoiseSigma", 0.1);
            asSensor.Injector    = DeterministicInjector("NoiseSigma", 0.1);
            pitchSensor.Injector = DeterministicInjector("NoiseSigma", 0.3);
            rollSensor.Injector  = DeterministicInjector("NoiseSigma", 0.3);
            tempSensor.Injector  = DeterministicInjector("NoiseSigma", 0.5);
            oilSensor.Injector   = DeterministicInjector("NoiseSigma", 0.2);

            % Inject mismatch by biasing one or both channels during the same window
            switch mismatchMode
                case "VS_BIAS"
                    vsSensor.Injector = DeterministicInjector( ...
                        "NoiseSigma", 0.1, ...
                        "Enabled", true, ...
                        "FaultType", "BIAS", ...
                        "FaultStartTime", mismatchStart, ...
                        "FaultDuration", mismatchDuration, ...
                        "BiasMagnitude", mismatchMag);

                case "ALT_BIAS"
                    altSensor.Injector = DeterministicInjector( ...
                        "NoiseSigma", 0.3, ...
                        "Enabled", true, ...
                        "FaultType", "BIAS", ...
                        "FaultStartTime", mismatchStart, ...
                        "FaultDuration", mismatchDuration, ...
                        "BiasMagnitude", mismatchMag);

                case "BOTH"
                    % Opposite-signed biases make mismatch stronger
                    altBias = mismatchMag/2;
                    vsBias  = -mismatchMag/2;

                    altSensor.Injector = DeterministicInjector( ...
                        "NoiseSigma", 0.3, ...
                        "Enabled", true, ...
                        "FaultType", "BIAS", ...
                        "FaultStartTime", mismatchStart, ...
                        "FaultDuration", mismatchDuration, ...
                        "BiasMagnitude", altBias);

                    vsSensor.Injector = DeterministicInjector( ...
                        "NoiseSigma", 0.1, ...
                        "Enabled", true, ...
                        "FaultType", "BIAS", ...
                        "FaultStartTime", mismatchStart, ...
                        "FaultDuration", mismatchDuration, ...
                        "BiasMagnitude", vsBias);
            end

            warnDetectedThisRun = false;
            faultDetectedThisRun = false;
            warnDetectionTime = NaN;
            faultDetectionTime = NaN;
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

    %% Storage
    sensorStates = strings(length(t), 7);
    systemStates = strings(length(t), 1);

    altC_hist = nan(length(t),1);
    vsC_hist  = nan(length(t),1);
    sysStateNum = nan(length(t),1);

    %% Time loop
    for k = 1:length(t)
        tt = t(k);

        altT = trueAlt(tt);
        vsT  = trueVS(tt);
        asT  = trueAS(tt);
        pitT = truePitch(tt);
        rolT = trueRoll(tt);
        tmpT = trueTemp(tt);
        oilT = trueOil(tt);

        [altMeas, ~] = altSensor.step(altT);
        [vsMeas,  ~] = vsSensor.step(vsT);
        [asMeas,  ~] = asSensor.step(asT);
        [pitMeas, ~] = pitchSensor.step(pitT);
        [rolMeas, ~] = rollSensor.step(rolT);
        [tmpMeas, ~] = tempSensor.step(tmpT);
        [oilMeas, ~] = oilSensor.step(oilT);

        [altC, altS] = altMon.step(altMeas);
        [vsC,  vsS ] = vsMon.step(vsMeas);
        [asC,  asS ] = asMon.step(asMeas);
        [pitC, pitS] = pitchMon.step(pitMeas);
        [rolC, rolS] = rollMon.step(rolMeas);
        [tmpC, tmpS] = tempMon.step(tmpMeas);
        [oilC, oilS] = oilMon.step(oilMeas);

        altC_hist(k) = altC;
        vsC_hist(k)  = vsC;

        if scenarioId == "MCV-2"
            switch targetSensor
                case "ALT"
                    targetState = altS;
                case "VS"
                    targetState = vsS;
                case "AS"
                    targetState = asS;
                case "PIT"
                    targetState = pitS;
                case "ROL"
                    targetState = rolS;
                case "TMP"
                    targetState = tmpS;
                case "OIL"
                    targetState = oilS;
            end

            if ~detectedThisRun && tt >= faultStart && (targetState == "SUSPECT" || targetState == "FAILED")
                detectedThisRun = true;
                detectionTime = tt;
            end
        end

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

        [state, ~, ~] = orchestrator.step(states, values, tt);

        if scenarioId == "MCV-3"
            if ~warnDetectedThisRun && tt >= mismatchStart && state == "WARN"
                warnDetectedThisRun = true;
                warnDetectionTime = tt;
            end

            if ~faultDetectedThisRun && tt >= mismatchStart && state == "FAULT"
                faultDetectedThisRun = true;
                faultDetectionTime = tt;
            end
        end

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

        if N == 1
            fprintf("t=%.2f  SYS=%s  ALT=%s  VS=%s  AS=%s  PIT=%s  ROL=%s  TMP=%s  OIL=%s\n", ...
                tt, state, altS, vsS, asS, pitS, rolS, tmpS, oilS);
        end

        if state == "WARN"
            warnPresent(k) = 1;
        end

        if state == "FAULT"
            faultPresent(k) = 1;
        end
    end

    %% Count state entries
    for i = 2:length(sysStateNum)
        if sysStateNum(i) == 1 && sysStateNum(i-1) ~= 1
            warnEvents = warnEvents + 1;
            thisRunWarnEntries = thisRunWarnEntries + 1;
        end

        if sysStateNum(i) == 2 && sysStateNum(i-1) ~= 2
            faultEvents = faultEvents + 1;
            thisRunFaultEntries = thisRunFaultEntries + 1;
        end
    end

    %% Store per-run outputs
    if any(sysStateNum == 1)
        warnOccured(run) = 1;
    end

    if any(sysStateNum == 2)
        faultOccured(run) = 1;
    end

    warnTimesteps(run, :) = warnPresent;

    warnEntriesPerRun(run) = thisRunWarnEntries;
    faultEntriesPerRun(run) = thisRunFaultEntries;
    warnTimestepsPerRun(run) = sum(warnPresent);
    faultTimestepsPerRun(run) = sum(faultPresent);

    if scenarioId == "MCV-2" && detectedThisRun
        detectedRuns(run) = 1;
        detectionDelayRuns(run) = max(0, detectionTime - faultStart);
    end

    if scenarioId == "MCV-3"
        if warnDetectedThisRun
            warnDetectedRuns_MCV3(run) = 1;
            warnDelayRuns_MCV3(run) = max(0, warnDetectionTime - mismatchStart);
        end

        if faultDetectedThisRun
            faultDetectedRuns_MCV3(run) = 1;
            faultDelayRuns_MCV3(run) = max(0, faultDetectionTime - mismatchStart);
        end
    end
end

%% Summary results
totalTimesteps = N * length(t);

warnEventRate = warnEvents / totalTimesteps;
faultEventRate = faultEvents / totalTimesteps;

warnRateRuns = sum(warnOccured == 1) / N;
warnRateTimestepsRows = sum(warnTimesteps == 1);
warnRateTimesteps = sum(warnRateTimestepsRows) / numel(warnTimesteps);
faultRate = sum(faultOccured == 1) / N;

fprintf("Monte Carlo Results for %d runs in scenario %s:\n", N, scenarioId)
fprintf("False WARN events: %d\n", warnEvents)
fprintf("WARN event rate: %.5f\n", warnEventRate)
fprintf("FAULT events: %d\n", faultEvents)
fprintf("FAULT event rate: %.5f\n", faultEventRate)

if scenarioId == "MCV-1"
    pWarnTimestepsOK  = mean(warnTimestepsPerRun  <= req.MCV1.maxWarnTimestepsPerRun)  * 100;
    pWarnTimestepsBad = mean(warnTimestepsPerRun  >  req.MCV1.maxWarnTimestepsPerRun)  * 100;

    pFaultTimestepsOK  = mean(faultTimestepsPerRun <= req.MCV1.maxFaultTimestepsPerRun) * 100;
    pFaultTimestepsBad = mean(faultTimestepsPerRun >  req.MCV1.maxFaultTimestepsPerRun) * 100;

    pWarnEntriesOK  = mean(warnEntriesPerRun <= req.MCV1.maxWarnEntriesPerRun) * 100;
    pWarnEntriesBad = mean(warnEntriesPerRun >  req.MCV1.maxWarnEntriesPerRun) * 100;

    pFaultEntriesOK  = mean(faultEntriesPerRun <= req.MCV1.maxFaultEntriesPerRun) * 100;
    pFaultEntriesBad = mean(faultEntriesPerRun >  req.MCV1.maxFaultEntriesPerRun) * 100;

    fprintf("\nMCV-1 Requirement Check:\n");
    fprintf("WARN timesteps/run <= %g: %.2f %% of runs, > threshold: %.2f %%\n", ...
        req.MCV1.maxWarnTimestepsPerRun, pWarnTimestepsOK, pWarnTimestepsBad);
    fprintf("FAULT timesteps/run <= %g: %.2f %% of runs, > threshold: %.2f %%\n", ...
        req.MCV1.maxFaultTimestepsPerRun, pFaultTimestepsOK, pFaultTimestepsBad);
    fprintf("WARN entries/run <= %g: %.2f %% of runs, > threshold: %.2f %%\n", ...
        req.MCV1.maxWarnEntriesPerRun, pWarnEntriesOK, pWarnEntriesBad);
    fprintf("FAULT entries/run <= %g: %.2f %% of runs, > threshold: %.2f %%\n", ...
        req.MCV1.maxFaultEntriesPerRun, pFaultEntriesOK, pFaultEntriesBad);

    figure
    bar([warnEventRate*100 faultEventRate*100])
    ylabel("Percentage (%)")
    xticklabels(["False WARN","False FAULT"])
    title("Monte Carlo Robustness Results")
    grid on

    plotDistributionWithRequirement(warnTimestepsPerRun, req.MCV1.maxWarnTimestepsPerRun, ...
        "MCV-1 Distribution: False WARN Timesteps per Run", "False WARN timesteps per run");

    plotDistributionWithRequirement(faultTimestepsPerRun, req.MCV1.maxFaultTimestepsPerRun, ...
        "MCV-1 Distribution: False FAULT Timesteps per Run", "False FAULT timesteps per run");

    plotDistributionWithRequirement(warnEntriesPerRun, req.MCV1.maxWarnEntriesPerRun, ...
        "MCV-1 Distribution: False WARN Entries per Run", "False WARN entries per run");

    plotDistributionWithRequirement(faultEntriesPerRun, req.MCV1.maxFaultEntriesPerRun, ...
        "MCV-1 Distribution: False FAULT Entries per Run", "False FAULT entries per run");
end

if scenarioId == "MCV-2"
    detectionProbability = mean(detectedRuns) * 100;
    missedDetectionProbability = (1 - mean(detectedRuns)) * 100;

    validDelays = detectionDelayRuns(~isnan(detectionDelayRuns));

    if ~isempty(validDelays)
        fprintf("Min detection delay: %.4f s\n", min(validDelays));
        fprintf("Max detection delay: %.4f s\n", max(validDelays));
        fprintf("Mean detection delay: %.4f s\n", mean(validDelays));

        edges = -dt/2 : dt : (max(validDelays) + dt/2);

        binWidth = 0.001;

        figure
        histogram(validDelays, 'BinWidth', binWidth)
        hold on
        xline(req.MCV2.maxDetectionDelay, 'r--', 'LineWidth', 2)
        
        xlim([0 max(validDelays)+binWidth])
        xlabel("Detection delay (s)")
        ylabel("Count")
        title("MCV-2 Detection Delay Distribution")
        grid on
        
        pWithin = mean(validDelays <= req.MCV2.maxDetectionDelay) * 100;
        pBeyond = mean(validDelays > req.MCV2.maxDetectionDelay) * 100;
        
        txt = sprintf('Requirement threshold = %.2f s\nProportion <= threshold: %.2f %%\nProportion > threshold: %.2f %%', req.MCV2.maxDetectionDelay, pWithin, pBeyond);
        
        annotation("textbox", ...
            [0.58 0.68 0.25 0.12], ...
            "String", txt, ...
            "FitBoxToText", "on", ...
            "BackgroundColor", "white");
        
        hold off

        % Manual empirical CDF (no toolbox required)
        x = sort(validDelays);
        f = (1:length(x)) / length(x);

        figure
        plot(x, f, 'LineWidth', 2)
        hold on
        xline(req.MCV2.maxDetectionDelay, 'r--', 'LineWidth', 2)

        pWithin = mean(validDelays <= req.MCV2.maxDetectionDelay) * 100;

        xlabel("Detection delay (s)")
        ylabel("Cumulative probability")
        title("MCV-2 Detection Delay CDF")
        grid on

        txt = sprintf("P(delay <= %.2f s) = %.2f %%", ...
            req.MCV2.maxDetectionDelay, pWithin);

        annotation("textbox", ...
            [0.58 0.2 0.25 0.1], ...
            "String", txt, ...
            "FitBoxToText", "on", ...
            "BackgroundColor", "white");

        hold off
    end

    meanDetectionDelay = mean(validDelays);
    maxDetectionDelay = max(validDelays);

    fprintf("\nMCV-2 Detection Results:\n");
    fprintf("Detection probability: %.2f %%\n", detectionProbability);
    fprintf("Missed-detection probability: %.2f %%\n", missedDetectionProbability);
    fprintf("Mean detection delay: %.3f s\n", meanDetectionDelay);
    fprintf("Max detection delay: %.3f s\n", maxDetectionDelay);

    failureClasses = ["BIAS", "DRIFT", "STUCK", "DROPOUT"];
    fprintf("\nMCV-2 Detection Results by Fault Type:\n");

    for j = 1:length(failureClasses)
        thisFault = failureClasses(j);

        idx = (faultTypeRuns == thisFault);
        nFault = sum(idx);

        if nFault == 0
            fprintf("%s: no runs\n", thisFault);
            continue;
        end

        detProb = mean(detectedRuns(idx)) * 100;
        missProb = 100 - detProb;

        thisDelays = detectionDelayRuns(idx & ~isnan(detectionDelayRuns));

        if isempty(thisDelays)
            meanDelay = NaN;
            maxDelay = NaN;
        else
            meanDelay = mean(thisDelays);
            maxDelay = max(thisDelays);
        end

        fprintf("\nFault type: %s\n", thisFault);
        fprintf("  Runs: %d\n", nFault);
        fprintf("  Detection probability: %.2f %%\n", detProb);
        fprintf("  Missed-detection probability: %.2f %%\n", missProb);
        fprintf("  Mean detection delay: %.3f s\n", meanDelay);
        fprintf("  Max detection delay: %.3f s\n", maxDelay);
    end
end

if scenarioId == "MCV-3"
    warnDetectionProbability  = mean(warnDetectedRuns_MCV3) * 100;
    faultDetectionProbability = mean(faultDetectedRuns_MCV3) * 100;

    missedWarnProbability  = 100 - warnDetectionProbability;
    missedFaultProbability = 100 - faultDetectionProbability;

    validWarnDelays  = warnDelayRuns_MCV3(~isnan(warnDelayRuns_MCV3));
    validFaultDelays = faultDelayRuns_MCV3(~isnan(faultDelayRuns_MCV3));

    fprintf("\nMCV-3 Redundancy Mismatch Results:\n");
    fprintf("WARN detection probability: %.2f %%\n", warnDetectionProbability);
    fprintf("WARN missed-detection probability: %.2f %%\n", missedWarnProbability);

    if ~isempty(validWarnDelays)
        fprintf("WARN mean detection delay: %.3f s\n", mean(validWarnDelays));
        fprintf("WARN max detection delay: %.3f s\n", max(validWarnDelays));
    else
        fprintf("WARN mean detection delay: NaN\n");
        fprintf("WARN max detection delay: NaN\n");
    end

    fprintf("\nFAULT escalation probability: %.2f %%\n", faultDetectionProbability);
    fprintf("Runs with no FAULT escalation: %.2f %%\n", missedFaultProbability);

    if ~isempty(validFaultDelays)
        fprintf("FAULT mean escalation delay: %.3f s\n", mean(validFaultDelays));
        fprintf("FAULT max escalation delay: %.3f s\n", max(validFaultDelays));
    else
        fprintf("FAULT mean escalation delay: NaN\n");
        fprintf("FAULT max escalation delay: NaN\n");
    end

    % Requirement compliance
    pWarnWithinReq = mean(warnDelayRuns_MCV3 <= req.MCV3.maxWarnDetectionDelay, 'omitnan') * 100;
    pFaultWithinReq = mean(faultDelayRuns_MCV3 <= req.MCV3.maxFaultEscalationDelay, 'omitnan') * 100;

    fprintf("\nMCV-3 Requirement Check:\n");
    fprintf("WARN detection probability >= %.2f %% ?  Actual: %.2f %%\n", ...
        req.MCV3.minWarnDetectionProbability, warnDetectionProbability);
    fprintf("WARN delay <= %.2f s among detected runs: %.2f %%\n", ...
        req.MCV3.maxWarnDetectionDelay, pWarnWithinReq);

    fprintf("FAULT escalation probability >= %.2f %% ?  Actual: %.2f %%\n", ...
        req.MCV3.minFaultEscalationProbability, faultDetectionProbability);
    fprintf("FAULT delay <= %.2f s among escalated runs: %.2f %%\n", ...
        req.MCV3.maxFaultEscalationDelay, pFaultWithinReq);

    % Bar chart: detection / escalation probabilities
    figure
    bar([warnDetectionProbability faultDetectionProbability])
    ylabel("Probability (%)")
    xticklabels(["WARN detected","FAULT escalated"])
    title("MCV-3 Redundancy Mismatch Detection/Escalation Probability")
    grid on

    % WARN delay histogram
    if ~isempty(validWarnDelays)
        figure
        histogram(validWarnDelays, 'BinWidth', dt)
        hold on
        xline(req.MCV3.maxWarnDetectionDelay, 'r--', 'LineWidth', 2)
        xlabel("WARN detection delay (s)")
        ylabel("Count")
        title("MCV-3 WARN Detection Delay Distribution")
        grid on

        txt = sprintf('Requirement threshold = %.2f s\n Proportion <= threshold: %.2f %%\n Proportion > threshold: %.2f %%', ...
            req.MCV3.maxWarnDetectionDelay, ...
            mean(validWarnDelays <= req.MCV3.maxWarnDetectionDelay)*100, ...
            mean(validWarnDelays > req.MCV3.maxWarnDetectionDelay)*100);

        annotation("textbox", [0.58 0.68 0.25 0.12], ...
            "String", txt, ...
            "FitBoxToText", "on", ...
            "BackgroundColor", "white");
        hold off
    end

    % FAULT delay histogram
    if ~isempty(validFaultDelays)
        figure
        histogram(validFaultDelays, 'BinWidth', dt)
        hold on
        xline(req.MCV3.maxFaultEscalationDelay, 'r--', 'LineWidth', 2)
        xlabel("FAULT escalation delay (s)")
        ylabel("Count")
        title("MCV-3 FAULT Escalation Delay Distribution")
        grid on

        txt = sprintf('Requirement threshold = %.2f s\n Proportion <= threshold: %.2f %%\n" Proportion > threshold: %.2f %%', ...
            req.MCV3.maxFaultEscalationDelay, ...
            mean(validFaultDelays <= req.MCV3.maxFaultEscalationDelay)*100, ...
            mean(validFaultDelays > req.MCV3.maxFaultEscalationDelay)*100);

        annotation("textbox", [0.58 0.68 0.25 0.12], ...
            "String", txt, ...
            "FitBoxToText", "on", ...
            "BackgroundColor", "white");
        hold off
    end

    % Breakdown by mismatch mode
    mismatchModes = ["VS_BIAS", "ALT_BIAS", "BOTH"];
    fprintf("\nMCV-3 Results by Mismatch Mode:\n");

    for j = 1:length(mismatchModes)
        thisMode = mismatchModes(j);
        idx = (mismatchModeRuns == thisMode);
        nMode = sum(idx);

        if nMode == 0
            fprintf("%s: no runs\n", thisMode);
            continue;
        end

        warnProb_j  = mean(warnDetectedRuns_MCV3(idx)) * 100;
        faultProb_j = mean(faultDetectedRuns_MCV3(idx)) * 100;

        warnDelays_j  = warnDelayRuns_MCV3(idx & ~isnan(warnDelayRuns_MCV3));
        faultDelays_j = faultDelayRuns_MCV3(idx & ~isnan(faultDelayRuns_MCV3));

        fprintf("\nMismatch mode: %s\n", thisMode);
        fprintf("  Runs: %d\n", nMode);
        fprintf("  WARN detection probability: %.2f %%\n", warnProb_j);
        fprintf("  FAULT escalation probability: %.2f %%\n", faultProb_j);

        if ~isempty(warnDelays_j)
            fprintf("  WARN mean delay: %.3f s\n", mean(warnDelays_j));
            fprintf("  WARN max delay: %.3f s\n", max(warnDelays_j));
        else
            fprintf("  WARN mean delay: NaN\n");
            fprintf("  WARN max delay: NaN\n");
        end

        if ~isempty(faultDelays_j)
            fprintf("  FAULT mean delay: %.3f s\n", mean(faultDelays_j));
            fprintf("  FAULT max delay: %.3f s\n", max(faultDelays_j));
        else
            fprintf("  FAULT mean delay: NaN\n");
            fprintf("  FAULT max delay: NaN\n");
        end
    end
end

disp("Scenario complete.");

%% Local helper function
function classId = FaultClassifier(meta)
    classId = 0;

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

function plotDistributionWithRequirement(dataVec, threshold, plotTitleStr, xLabelStr)
    dataVec = dataVec(~isnan(dataVec));

    if isempty(dataVec)
        warning("No valid data for plot: %s", plotTitleStr);
        return;
    end

    pBelowEq = mean(dataVec <= threshold) * 100;
    pAbove   = mean(dataVec > threshold) * 100;

    figure
    histogram(dataVec)
    hold on
    xline(threshold, 'r--', 'LineWidth', 2);

    xlabel(xLabelStr)
    ylabel("Count")
    title(plotTitleStr)
    grid on

    txt = sprintf(["Requirement threshold = %.3f\n"
        "Proportion <= threshold: %.2f %%\n"
        "Proportion > threshold: %.2f %%"], threshold, pBelowEq, pAbove);

    annotation("textbox", ...
        [0.62 0.68 0.25 0.18], ...
        "String", txt, ...
        "FitBoxToText", "on", ...
        "BackgroundColor", "white");

    hold off
end
