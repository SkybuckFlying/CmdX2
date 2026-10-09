program TestCmdX2;

{$APPTYPE CONSOLE}

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

uses
  SysUtils,
  Classes,
  CmdX2Types,
  CmdX2Config,
  CmdX2Path,
  CmdX2Resolver,
  CmdX2Env,
  CmdX2Probe,
  CmdX2Parser,
  CmdX2Exec,
  CmdX2Batch,
  CmdX2Diagnostics,
  CmdX2Builtins;

var
  Session: TSession;
  PassedCount, FailedCount: Integer;

procedure AssertTrue(const AMessage: Boolean; const ATestName: string);
begin
  if AMessage then
  begin
    Writeln('[PASS] ', ATestName);
    Inc(PassedCount);
  end
  else
  begin
    Writeln('[FAIL] ', ATestName);
    Inc(FailedCount);
  end;
end;

procedure TestVariableExpansion;
var
  Res: string;
begin
  Session.Environment.AddOrSetValue('MY_VAR', 'HelloWorld');
  Res := ExpandVariables('Echo %MY_VAR%!', Session);
  AssertTrue(Res = 'Echo HelloWorld!', 'Variable expansion %MY_VAR%');
end;

procedure TestResolverAndBuiltins;
begin
  AssertTrue(IsBuiltInCommand('dir'), 'Builtin check: dir');
  AssertTrue(IsBuiltInCommand('cmdx2'), 'Builtin check: cmdx2');
  AssertTrue(not IsBuiltInCommand('custom_unknown_tool'), 'Non-builtin check');
end;

procedure TestPathStressTest;
var
  I: Integer;
  EntrySource: TPathEntrySource;
  CharCount, EntryCount: Integer;
  ByteSize: Int64;
  ResolvedPath, MatchedExt: string;
  PathIdx: Integer;
  TargetDir, TargetExe: string;
begin
  Session.PathEntries.Clear;
  TargetDir := ExtractFilePath(ParamStr(0));
  TargetExe := ExtractFileName(ParamStr(0));

  for I := 1 to 10000 do
  begin
    EntrySource.Path := 'C:\LongToolsDirectoryPath\SubToolDirectoryFolder_' + IntToStr(I) + '\BinDirectory_' + IntToStr(I);
    EntrySource.SourceFile := 'StressTest';
    EntrySource.Priority := 1;
    Session.PathEntries.Add(EntrySource);

    if I = 5000 then
    begin
      EntrySource.Path := TargetDir;
      EntrySource.SourceFile := 'StressTestTarget';
      EntrySource.Priority := 1;
      Session.PathEntries.Add(EntrySource);
    end;
  end;

  RebuildInMemoryPath(Session);
  GetPathLengthStats(Session, CharCount, EntryCount, ByteSize);

  AssertTrue(EntryCount >= 10000, 'PATH stress test entry count >= 10,000');
  AssertTrue(ByteSize >= 500000, 'PATH stress test size >= 500 KB');

  AssertTrue(ResolveCommand(Session, TargetExe, ResolvedPath, MatchedExt, PathIdx),
             'Command resolution in 10,000 entry long PATH');
end;

procedure TestEnvironmentBlock;
var
  BlockPtr: Pointer;
  BlockSize: Int64;
begin
  BlockPtr := BuildEnvironmentBlockUTF16(Session.Environment, BlockSize);
  try
    AssertTrue(Assigned(BlockPtr), 'Environment block pointer allocated');
    AssertTrue(BlockSize > 0, 'Environment block size > 0');
  finally
    FreeEnvironmentBlockUTF16(BlockPtr);
  end;
end;

begin
  PassedCount := 0;
  FailedCount := 0;

  InitSession(Session);
  try
    LoadCurrentEnvironment(Session);
    PerformCeilingProbe(Session, False);

    Writeln('=== Running CmdX2 Test Suite ===');
    TestVariableExpansion;
    TestResolverAndBuiltins;
    TestEnvironmentBlock;
    TestPathStressTest;

    Writeln;
    Writeln(Format('Test Summary: %d Passed, %d Failed.', [PassedCount, FailedCount]));

    if FailedCount > 0 then
      Halt(1)
    else
      Halt(0);

  finally
    FreeSession(Session);
  end;
end.
