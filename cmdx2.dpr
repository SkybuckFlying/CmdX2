program cmdx2;

{$APPTYPE CONSOLE}

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

uses
  SysUtils,
  Classes,
  CmdX2Types in 'CmdX2Types.pas',
  CmdX2Config in 'CmdX2Config.pas',
  CmdX2Path in 'CmdX2Path.pas',
  CmdX2Resolver in 'CmdX2Resolver.pas',
  CmdX2Env in 'CmdX2Env.pas',
  CmdX2Probe in 'CmdX2Probe.pas',
  CmdX2Parser in 'CmdX2Parser.pas',
  CmdX2Exec in 'CmdX2Exec.pas',
  CmdX2Batch in 'CmdX2Batch.pas',
  CmdX2Diagnostics in 'CmdX2Diagnostics.pas',
  CmdX2Builtins in 'CmdX2Builtins.pas';

var
  Session: TSession;
  InputLine: string;
  ParsedCmds: TParsedCommandLine;
  BatchFile: string;
  BatchArgs: TStringList;

procedure ProcessArgs;
var
  Idx: Integer;
  Arg: string;
begin
  Idx := 1;
  while Idx <= ParamCount do
  begin
    Arg := ParamStr(Idx);
    if SameText(Arg, '/c') or SameText(Arg, '-c') then
    begin
      if Idx < ParamCount then
      begin
        Inc(Idx);
        InputLine := ParamStr(Idx);
        ParsedCmds := ParseCommandLine(InputLine, Session);
        try
          ExecuteParsedCommandLine(Session, ParsedCmds);
        finally
          FreeParsedCommandLine(ParsedCmds);
        end;
        Halt(Session.ErrorLevel);
      end;
    end
    else if SameText(Arg, '--config') then
    begin
      if Idx < ParamCount then
      begin
        Inc(Idx);
        LoadAllConfigs(Session, ParamStr(Idx));
      end;
    end
    else if FileExists(Arg) and (SameText(ExtractFileExt(Arg), '.bat') or SameText(ExtractFileExt(Arg), '.cmd')) then
    begin
      BatchFile := Arg;
      BatchArgs := TStringList.Create;
      try
        Inc(Idx);
        while Idx <= ParamCount do
        begin
          BatchArgs.Add(ParamStr(Idx));
          Inc(Idx);
        end;
        ExecuteBatchFile(Session, BatchFile, BatchArgs);
      finally
        BatchArgs.Free;
      end;
      Halt(Session.ErrorLevel);
    end;
    Inc(Idx);
  end;
end;

begin
  try
    InitSession(Session);
    try
      LoadCurrentEnvironment(Session);
      LoadAllConfigs(Session);
      RebuildInMemoryPath(Session);
      PerformCeilingProbe(Session, False);

      if ParamCount > 0 then
      begin
        ProcessArgs;
      end;

      Writeln('CmdX2 [Version 2.0.0]');
      Writeln('A cmd.exe-compatible shell removing PATH length limits.');
      Writeln('Type "exit" to quit, or "cmdx2 limits" for PATH diagnostics.');
      Writeln;

      while not Session.ShouldExit do
      begin
        Write(Session.Cwd + '> ');
        Readln(InputLine);
        InputLine := Trim(InputLine);

        if InputLine <> '' then
        begin
          ParsedCmds := ParseCommandLine(InputLine, Session);
          try
            ExecuteParsedCommandLine(Session, ParsedCmds);
          finally
            FreeParsedCommandLine(ParsedCmds);
          end;
        end;
      end;

    finally
      FreeSession(Session);
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'Fatal Error: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
