unit CmdX2Types;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections;

type
  ECmdX2Exception = class(Exception);

  TExecStrategy = (esWarnAndProceed, esTrimSessionUsed, esShimDirectory, esRefuseAndExplain);

  TEnvironmentMap = TDictionary<string, string>;

  TPathEntrySource = record
    Path: string;
    SourceFile: string;
    Priority: Integer; // 1: Session, 2: Project, 3: Machine, 4: Global
  end;

  TLimits = record
    MeasuredCeiling: Int64; // bytes
    ProbeSucceeded: Boolean;
    CachedAt: TDateTime;
    WindowsBuild: Integer;
  end;

  TProbeConfig = record
    Enabled: Boolean;
    CachedCeiling: Int64;
  end;

  TPathConfig = record
    Entries: TStringList;
    AppendSystem: Boolean;
    Deduplicate: Boolean;
    Normalize: Boolean;
  end;

  TPathextConfig = record
    Extensions: TStringList;
  end;

  TConfig = record
    PathConfig: TPathConfig;
    PathextConfig: TPathextConfig;
    ProbeConfig: TProbeConfig;
    Strategy: TExecStrategy;
    WarnThreshold: Double;
  end;

  TBatchContext = record
    FilePath: string;
    CurrentLine: Integer;
  end;

  TSession = record
    Environment: TEnvironmentMap;
    RawPath: string;
    PathEntries: TList<TPathEntrySource>;
    PathExtList: TStringList;
    Cwd: string;
    Drive: Char;
    ErrorLevel: Integer;
    SetLocalStack: TList<TEnvironmentMap>;
    BatchStack: TList<TBatchContext>;
    UsedEntries: TDictionary<string, Boolean>;
    ResolverCache: TDictionary<string, string>;
    Limits: TLimits;
    Config: TConfig;
    ShouldExit: Boolean;
  end;

  PSession = ^TSession;

procedure InitConfig(var AConfig: TConfig);
procedure FreeConfig(var AConfig: TConfig);
procedure InitSession(var ASession: TSession);
procedure FreeSession(var ASession: TSession);

implementation

procedure InitConfig(var AConfig: TConfig);
begin
  AConfig.PathConfig.Entries := TStringList.Create;
  AConfig.PathConfig.AppendSystem := True;
  AConfig.PathConfig.Deduplicate := True;
  AConfig.PathConfig.Normalize := True;

  AConfig.PathextConfig.Extensions := TStringList.Create;
  AConfig.PathextConfig.Extensions.Add('.COM');
  AConfig.PathextConfig.Extensions.Add('.EXE');
  AConfig.PathextConfig.Extensions.Add('.BAT');
  AConfig.PathextConfig.Extensions.Add('.CMD');
  AConfig.PathextConfig.Extensions.Add('.PS1');
  AConfig.PathextConfig.Extensions.Add('.VBS');

  AConfig.ProbeConfig.Enabled := True;
  AConfig.ProbeConfig.CachedCeiling := 0;

  AConfig.Strategy := esWarnAndProceed;
  AConfig.WarnThreshold := 0.90;
end;

procedure FreeConfig(var AConfig: TConfig);
begin
  FreeAndNil(AConfig.PathConfig.Entries);
  FreeAndNil(AConfig.PathextConfig.Extensions);
end;

procedure InitSession(var ASession: TSession);
begin
  ASession.Environment := TEnvironmentMap.Create;
  ASession.RawPath := '';
  ASession.PathEntries := TList<TPathEntrySource>.Create;
  ASession.PathExtList := TStringList.Create;
  ASession.Cwd := GetCurrentDir;
  if Length(ASession.Cwd) >= 1 then
    ASession.Drive := ASession.Cwd[1]
  else
    ASession.Drive := 'C';
  ASession.ErrorLevel := 0;
  ASession.SetLocalStack := TList<TEnvironmentMap>.Create;
  ASession.BatchStack := TList<TBatchContext>.Create;
  ASession.UsedEntries := TDictionary<string, Boolean>.Create;
  ASession.ResolverCache := TDictionary<string, string>.Create;
  ASession.Limits.MeasuredCeiling := 65534;
  ASession.Limits.ProbeSucceeded := False;
  ASession.Limits.CachedAt := 0;
  ASession.Limits.WindowsBuild := 0;
  ASession.ShouldExit := False;

  InitConfig(ASession.Config);
end;

procedure FreeSession(var ASession: TSession);
var
  I: Integer;
begin
  if Assigned(ASession.Environment) then
    FreeAndNil(ASession.Environment);
  if Assigned(ASession.PathEntries) then
    FreeAndNil(ASession.PathEntries);
  if Assigned(ASession.PathExtList) then
    FreeAndNil(ASession.PathExtList);

  if Assigned(ASession.SetLocalStack) then
  begin
    for I := 0 to ASession.SetLocalStack.Count - 1 do
      ASession.SetLocalStack[I].Free;
    FreeAndNil(ASession.SetLocalStack);
  end;

  if Assigned(ASession.BatchStack) then
    FreeAndNil(ASession.BatchStack);
  if Assigned(ASession.UsedEntries) then
    FreeAndNil(ASession.UsedEntries);
  if Assigned(ASession.ResolverCache) then
    FreeAndNil(ASession.ResolverCache);

  FreeConfig(ASession.Config);
end;

end.
