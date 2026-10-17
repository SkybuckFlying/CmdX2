unit CmdX2Diagnostics;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections, CmdX2Types;

procedure PrintEnvDump(ASession: TSession);
procedure PrintLimitsReport(ASession: TSession);

implementation

procedure PrintEnvDump(ASession: TSession);
var
  Key, Val: string;
begin
  for Key in ASession.Environment.Keys do
    if ASession.Environment.TryGetValue(Key, Val) then
      Writeln(Format('%s=%s (%d chars)', [Key, Val, Length(Val)]));
end;

procedure PrintLimitsReport(ASession: TSession);
begin
  Writeln('In-memory PATH length: ', Length(ASession.RawPath), ' chars');
  Writeln('Entry count:           ', ASession.PathEntries.Count);
  Writeln('Per-variable limit:    ', CMDX2_ENV_VAR_LIMIT_CHARS, ' chars');
  Writeln('cmd.exe discard limit: ', CMDX2_CMD_INHERIT_LIMIT_CHARS, ' chars');
end;

end.