unit CmdX2Batch;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, CmdX2Types, CmdX2Parser, CmdX2Exec;

function ExecuteBatchFile(var ASession: TSession; const ABatchPath: string; AArgs: TStringList): Integer;

implementation

function ExecuteBatchFile(var ASession: TSession; const ABatchPath: string; AArgs: TStringList): Integer;
var
  Lines: TStringList;
  I: Integer;
  Line, Trimmed, CleanLine: string;
  BatchCtx: TBatchContext;
  ParsedCmds: TParsedCommandLine;
  EchoState: Boolean;
begin
  Result := 0;
  if not FileExists(ABatchPath) then
  begin
    Writeln(ErrOutput, 'Batch file not found: ', ABatchPath);
    ASession.ErrorLevel := 9009;
    Exit(9009);
  end;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(ABatchPath);
    EchoState := True;

    BatchCtx.FilePath := ABatchPath;
    BatchCtx.CurrentLine := 0;
    ASession.BatchStack.Add(BatchCtx);

    try
      I := 0;
      while (I < Lines.Count) and (not ASession.ShouldExit) do
      begin
        BatchCtx.CurrentLine := I + 1;
        ASession.BatchStack[ASession.BatchStack.Count - 1] := BatchCtx;

        Line := Lines[I];
        Trimmed := Trim(Line);

        if (Trimmed = '') or (Copy(Trimmed, 1, 2) = '::') or (SameText(Copy(Trimmed, 1, 3), 'rem')) then
        begin
          Inc(I);
          Continue;
        end;

        CleanLine := Trimmed;
        if CleanLine[1] = '@' then
          CleanLine := Trim(Copy(CleanLine, 2, Length(CleanLine)));

        if SameText(CleanLine, 'echo off') then
        begin
          EchoState := False;
          Inc(I);
          Continue;
        end;

        if SameText(CleanLine, 'echo on') then
        begin
          EchoState := True;
          Inc(I);
          Continue;
        end;

        if (Trimmed[1] <> '@') and EchoState then
          Writeln(Line);

        if (Length(CleanLine) > 0) and (CleanLine[1] = ':') then
        begin
          Inc(I);
          Continue;
        end;

        ParsedCmds := ParseCommandLine(CleanLine, ASession);
        try
          Result := ExecuteParsedCommandLine(ASession, ParsedCmds);
        finally
          FreeParsedCommandLine(ParsedCmds);
        end;

        Inc(I);
      end;
    finally
      if ASession.BatchStack.Count > 0 then
        ASession.BatchStack.Delete(ASession.BatchStack.Count - 1);
    end;
  finally
    Lines.Free;
  end;
end;

end.
