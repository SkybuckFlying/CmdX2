unit CmdX2Types;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections, Generics.Defaults;

type
  TEnvironmentMap = TDictionary<string, string>;

  TBatchReturnPoint = record
    Line: Integer;
    Arg0: string;
    Args: TStringList;
  end;

  TBatchFrame = class
  public
    FilePath: string;
    Lines: TStringList;
    CurrentLine: Integer;
    Labels: TDictionary<string, Integer>;
    Arg0: string;
    Args: TStringList;
    EchoState: Boolean;
    DelayedExpansionState: Boolean;
    ReturnStack: TList<TBatchReturnPoint>;
    constructor Create;
    destructor Destroy; override;
  end;

  TSession = class
  public
    Environment: TEnvironmentMap;
    MachineRawPath: string;
    UserRawPath: string;
    MachinePathType: string;
    UserPathType: string;
    RawPath: string;
    PathEntries: TList<string>;
    PathExtList: TStringList;
    PerDriveCwd: TDictionary<Char, string>;
    Cwd: string;
    ErrorLevel: Integer;
    ShouldExit: Boolean;
    SetLocalStack: TList<TEnvironmentMap>;
    DelayedExpansion: Boolean;
    DelayedStack: TList<Boolean>;
    BatchStack: TObjectList<TBatchFrame>;
    DirectoryStack: TStringList;
    ResolverCache: TDictionary<string, string>;
    constructor Create;
    destructor Destroy; override;
  end;

const
  CMDX2_ENV_VAR_LIMIT_CHARS     = 32767;
  CMDX2_CMD_INHERIT_LIMIT_CHARS = 8191;
  CMDX2_CMDLINE_LIMIT_CHARS     = 32766;
  CMDX2_MAX_PIPE_STAGES         = 64;
  CMDX2_MAX_BATCH_RECURSION     = 32;
  CMDX2_MAX_SETLOCAL_DEPTH      = 32;
  CMDX2_MAX_GROUP_DEPTH         = 32;

function NewEnvironmentMap: TEnvironmentMap;

implementation

function EnvKeysEqual(const L, R: string): Boolean;
begin
  Result := CompareText(L, R) = 0;
end;

function EnvKeyHash(const V: string): Integer;
var
  Lower: string;
  I: Integer;
  H: Cardinal;
begin
  Lower := LowerCase(V);
  H := 0;
  // Hash accumulation intentionally wraps; disable overflow/range checks
  // around this loop only. The directives restore the project defaults
  // immediately after.
{$IFOPT Q+}{$DEFINE RESTORE_Q}{$Q-}{$ENDIF}
{$IFOPT R+}{$DEFINE RESTORE_R}{$R-}{$ENDIF}
  for I := 1 to Length(Lower) do
    H := H * 31 + Ord(Lower[I]);
{$IFDEF RESTORE_Q}{$Q+}{$UNDEF RESTORE_Q}{$ENDIF}
{$IFDEF RESTORE_R}{$R+}{$UNDEF RESTORE_R}{$ENDIF}
  Result := Integer(H);
end;

function NewEnvironmentMap: TEnvironmentMap;
var
  Comparer: IEqualityComparer<string>;
begin
  Comparer := TEqualityComparer<string>.Construct(EnvKeysEqual, EnvKeyHash);
  Result := TEnvironmentMap.Create(Comparer);
end;

{ TBatchFrame }

constructor TBatchFrame.Create;
begin
  inherited Create;
  FilePath := '';
  Lines := TStringList.Create;
  CurrentLine := 0;
  Labels := TDictionary<string, Integer>.Create;
  Arg0 := '';
  Args := TStringList.Create;
  EchoState := True;
  DelayedExpansionState := False;
  ReturnStack := TList<TBatchReturnPoint>.Create;
end;

destructor TBatchFrame.Destroy;
var
  I: Integer;
begin
  Lines.Free;
  Labels.Free;
  Args.Free;
  for I := 0 to ReturnStack.Count - 1 do
    ReturnStack[I].Args.Free;
  ReturnStack.Free;
  inherited;
end;

{ TSession }

constructor TSession.Create;
begin
  inherited Create;
  Environment := NewEnvironmentMap;
  MachineRawPath := '';
  UserRawPath := '';
  MachinePathType := '';
  UserPathType := '';
  RawPath := '';
  PathEntries := TList<string>.Create;
  PathExtList := TStringList.Create;
  PathExtList.Add('.COM');
  PathExtList.Add('.EXE');
  PathExtList.Add('.BAT');
  PathExtList.Add('.CMD');
  PathExtList.Add('.PS1');
  PathExtList.Add('.VBS');
  PerDriveCwd := TDictionary<Char, string>.Create;
  Cwd := GetCurrentDir;
  ErrorLevel := 0;
  ShouldExit := False;
  SetLocalStack := TList<TEnvironmentMap>.Create;
  DelayedExpansion := False;
  DelayedStack := TList<Boolean>.Create;
  BatchStack := TObjectList<TBatchFrame>.Create(True);
  DirectoryStack := TStringList.Create;
  ResolverCache := TDictionary<string, string>.Create;
end;

destructor TSession.Destroy;
var
  I: Integer;
begin
  Environment.Free;
  PathEntries.Free;
  PathExtList.Free;
  PerDriveCwd.Free;
  for I := 0 to SetLocalStack.Count - 1 do
    SetLocalStack[I].Free;
  SetLocalStack.Free;
  DelayedStack.Free;
  BatchStack.Free;
  DirectoryStack.Free;
  ResolverCache.Free;
  inherited;
end;

end.