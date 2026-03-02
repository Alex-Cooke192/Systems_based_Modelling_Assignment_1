% Example script usage
inj = Injector();
inj.Sigma = 2.0;
inj.EnableNoise = true;

alt = AltitudeSensorSITL( ...
    "Fs", 50, ...
    "AltMin", -500, ...
    "AltMax", 20000, ...
    "T_stable", 1.0, ...
    "T_fail", 0.5, ...
    "T_recover", 2.0, ...
    "Injector", inj);

injP = SimpleInjector(); injP.Sigma = 0.3;   % pitch noise (deg)
injR = SimpleInjector(); injR.Sigma = 0.5;   % roll noise (deg)
injV = SimpleInjector(); injV.Sigma = 0.8;   % VS noise (m/s)
injT = SimpleInjector(); injT.Sigma = 0.8;     % degC noise
injP = SimpleInjector(); injP.Sigma = 5;       % kPa noise

pitch = PitchSensorSITL("Injector", injP);
roll  = RollSensorSITL("Injector", injR);
vs    = VerticalSpeedSensorSITL("Injector", injV);
engT = EngineTempSensorSITL("Injector", injT);
oilP = OilPressureSensorSITL("Injector", injP);

[pitchDeg, pState] = pitch.step(truePitchDeg);
[rollDeg,  rState] = roll.step(trueRollDeg);
[vsMs,     vState] = vs.step(trueVS);
[Tc, tState] = engT.step(trueEngineTempDegC);
[Pk, pState] = oilP.step(trueOilPressurekPa);

T = 10; dt = 1/50;
t = 0:dt:T;
trueAlt = 1000 + 2*t;  % simple climb

stateLog = strings(size(t));
condLog = zeros(size(t));

for i = 1:numel(t)
    % Fault injection example: dropout between 3s and 3.4s
    inj.DropoutActive = (t(i) >= 3.0 && t(i) < 3.4);

    [condAlt, st, flags] = alt.step(trueAlt(i), t(i)); %#ok<NASGU>
    condLog(i) = condAlt;
    stateLog(i) = st;
end

disp([t(1:10).', condLog(1:10).', stateLog(1:10)])