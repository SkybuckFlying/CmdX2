unit CmdX2Diagnostics;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, CmdX2Types, CmdX2Path, CmdX2Env;

procedure PrintLimitsReport(const ASession: TSession);
procedure PrintPathReport(const ASession: TSession; ARaw, ALengthOnly, ADuplicatesOnly: Boolean);
procedure PrintEnvDump(const ASession: TSession);
procedure DiagnoseCommand(var ASession: TSession; const ACmdName: string);
procedure WriteLog(const ALogPath, AMessage: string);

implementation

procedure PrintLimitsReport(const ASession: TSession);
var
  CharCount, EntryCount: Integer;
  ByteSize, Headroom: Int64;
  Status: string;
begin
  CharCount := Length(ASession.RawPath);
  EntryCount := ASession.PathEntries.Count;
  ByteSize := CharCount * SizeOf(Char);
  Headroom := ASession.Limits.MeasuredCeiling - ByteSize;

  if Headroom < 0 then
    Status := 'EXCEEDED'
  else if Headroom < (ASession.Limits.MeasuredCeiling div 10) then
    Status := 'WARNING'
  else
    Status := 'OK';

  Writeln('Measured child environment ceiling: ', ASession.Limits.MeasuredCeiling, ' bytes');
  Writeln('In-memory PATH length:              ', ByteSize, ' bytes (', CharCount, ' chars, ', EntryCount, ' entries)');
  Writeln('Headroom:                           ', Headroom, ' bytes');
  Writeln('Status:                             ', Status);
end;

procedure PrintPathReport(const ASession: TSession; ARaw, ALengthOnly, ADuplicatesOnly: Boolean);
var
  I, CharCount, EntryCount: Integer;
  ByteSize: Int64;
  Entry: TPathEntrySource;
begin
  if ARaw then
  begin
    Writeln(ASession.RawPath);
    Exit;
  end;

  if ALengthOnly then
  begin
    CharCount := Length(ASession.RawPath);
    EntryCount := ASession.PathEntries.Count;
    ByteSize := CharCount * SizeOf(Char);
    Writeln(Format('Chars: %d, Entries: %d, Bytes: %d, Ceiling: %d',
           [CharCount, EntryCount, ByteSize, ASession.Limits.MeasuredCeiling]));
    Exit;
  end;

  Writeln('Index | Path Entry | Source File');
  Writeln('--------------------------------------------------------------------------------');
  for I := 0 to ASession.PathEntries.Count - 1 do
  begin
    Entry := ASession.PathEntries[I];
    Writeln(Format('%5d | %s | %s', [I + 1, Entry.Path, Entry.SourceFile]));
  end;
end;

procedure PrintEnvDump(const ASession: TSession);
var
  Key, Val: string;
begin
  for Key in ASession.Environment.Keys do
  begin
    if ASession.Environment.TryGetValue(Key, Val) then
      Writeln(Format('%s=%s (size: %d bytes)', [Key, Val, (Length(Key) + Length(Val) + 1) * SizeOf(Char)]));
  end;
end;

procedure DiagnoseCommand(var ASession: TSession; const ACmdName: string);
var
  BlockPtr: Pointer;
  BlockSize: Int64;
begin
  BlockPtr := BuildEnvironmentBlockUTF16(ASession.Environment, BlockSize);
  try
    Writeln('Diagnosing command execution for: ', ACmdName);
    Writeln('Constructed environment block size: ', BlockSize, ' bytes.');
    Writeln('Measured host ceiling:              ', ASession.Limits.MeasuredCeiling, ' bytes.');
    if BlockSize > ASession.Limits.MeasuredCeiling then
      Writeln('WARNING: Block size exceeds measured host ceiling! Execution will likely fail or require strategy trimming.')
    else
      Writeln('OK: Environment block fits within host ceiling.');
  finally
    FreeEnvironmentBlockUTF16(BlockPtr);
  end;
end;

procedure WriteLog(const ALogPath, AMessage: string);
var
  F: TextFile;
begin
  AssignFile(F, ALogPath);
  if FileExists(ALogPath) then
    Append(F)
  else
    Rewrite(F);
  try
    Writeln(F, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' - ' + AMessage);
  finally
    CloseFile(F);
  end;
end;

end.
