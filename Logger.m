% Logger.m
% One CSV file per run. Appends one row per state change.
%
% Usage:
%   logger = Logger("Folder","logs");     % creates new run log file
%   logger.logStateChange("NORMAL", tt, "WARN");
%   logger.close();                       % optional

classdef Logger < handle
    properties (SetAccess = private)
        Filename (1,1) string = ""
        IsInitialized (1,1) logical = false
    end

    properties (Access = private)
        fid (1,1) double = -1
        NextID (1,1) double = 1
    end

    methods
        function obj = Logger(varargin)
            % Logger(Name,Value,...)
            % Options:
            %   "Folder" (string) default ""
            %   "Prefix" (string) default "log_"
            opts.Folder = "logs";
            opts.Prefix = "log_";

            for k = 1:2:numel(varargin)
                opts.(char(varargin{k})) = varargin{k+1};
            end

            obj.startRun(opts.Folder, opts.Prefix);
        end

        function startRun(obj, folder, prefix)
            if nargin < 2 || strlength(string(folder)) == 0
                folder = "";
            else
                folder = string(folder);
            end
            if nargin < 3 || strlength(string(prefix)) == 0
                prefix = "log_";
            else
                prefix = string(prefix);
            end

            if obj.IsInitialized
                obj.close();
            end

            if strlength(folder) > 0 && ~isfolder(folder)
                mkdir(folder);
            end

            % Filename-safe timestamp (no ":" characters)
            stamp = string(datetime("now"), "yyyy-MM-dd_HH-mm-ss-SSS");
            fname = prefix + stamp + ".csv";
            if strlength(folder) > 0
                fname = string(fullfile(folder, fname));
            end

            obj.Filename = fname;

            obj.fid = fopen(obj.Filename, "w");
            if obj.fid < 0
                error("Logger:FileOpenFailed", "Could not open log file: %s", obj.Filename);
            end

            % Header
            fprintf(obj.fid, "StateChangeID,PreviousState,Timestamp,simtime, NewState\n");

            obj.NextID = 1;
            obj.IsInitialized = true;
        end

        function logStateChange(obj, prevState, timestamp, simtime, newState)
            if ~obj.IsInitialized || obj.fid < 0
                error("Logger:NotInitialized", "Logger not initialized. Create Logger() or call startRun().");
            end

            prevState = string(prevState);
            newState  = string(newState);

            id = obj.NextID;
            obj.NextID = obj.NextID + 1;

            % Quote string fields for CSV safety
            fprintf(obj.fid, '%d,"%s","%s","%s", "%s"\n', id, prevState, timestamp, simtime, newState);
        end

        function logTime(obj, prevState, timestamp, simtime)
            if ~obj.IsInitialized || obj.fid < 0
                error("Logger:NotInitialized", "Logger not initialized. Create Logger() or call startRun().");
            end

            prevState = string(prevState); 

            id = obj.NextID;
            obj.NextID = obj.NextID + 1;

            disp("Simtime")
            disp(simtime)
            disp("Timestamp")
            disp(timestamp)

            % Quote string fields for CSV safety
            fprintf(obj.fid, '%d,"%s","%s","%.2f", "-"\n', id, prevState, timestamp, simtime);
        end 

        function close(obj)
            if obj.fid >= 0
                fclose(obj.fid);
            end
            obj.fid = -1;
            obj.IsInitialized = false;
        end

        function delete(obj)
            obj.close();
        end
    end
end