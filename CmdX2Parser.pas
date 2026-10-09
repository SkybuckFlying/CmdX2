unit CmdX2Parser;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections, CmdX2Types;

type
  TRedirectionType = (rtNone, rtInput, rtOutputOverwrite, rtOutputAppend, rtStderrOverwrite);

  TParsedCommand = record
    ProgramName: string;
    Args: TStringList;
    RedirInput: string;
    RedirOutput: string;
    RedirAppend: Boolean;
    RedirStderr: string;
    PipeToNext: Boolean;
    OpAnd: Boolean;
    OpOr: Boolean;
    OpSeq: Boolean;
  end;

  TParsedCommandLine = TList<TParsedCommand>;

function ExpandVariables(const AInput: string; const ASession: TSession): string;
function ParseCommandLine(const ACommandLine: string; const ASession: TSession): TParsedCommandLine;
procedure FreeParsedCommandLine(ACmdLine: TParsedCommandLine);

implementation

function ExpandVariables(const AInput: string; const ASession: TSession): string;
var
  I, Len: Integer;
  InPercent, InExclamation: Boolean;
  VarName, Val: string;
  Sb: TStringBuilder;
  Ch: Char;
begin
  Sb := TStringBuilder.Create;
  try
    I := 1;
    Len := Length(AInput);
    InPercent := False;
    InExclamation := False;
    VarName := '';

    while I <= Len do
    begin
      Ch := AInput[I];

      if Ch = '^' then
      begin
        if (I < Len) then
        begin
          Inc(I);
          Sb.Append(AInput[I]);
        end;
      end;

      if Ch = '%' then
      begin
        if InPercent then
        begin
          if ASession.Environment.TryGetValue(VarName, Val) then
            Sb.Append(Val)
          else if VarName <> '' then
            Sb.Append('%' + VarName + '%');
          InPercent := False;
          VarName := '';
        end
        else
        begin
          InPercent := True;
          VarName := '';
        end;
      end
      else if Ch = '!' then
      begin
        if InExclamation then
        begin
          if ASession.Environment.TryGetValue(VarName, Val) then
            Sb.Append(Val)
          else if VarName <> '' then
            Sb.Append('!' + VarName + '!');
          InExclamation := False;
          VarName := '';
        end
        else
        begin
          InExclamation := True;
          VarName := '';
        end;
      end
      else
      begin
        if InPercent or InExclamation then
          VarName := VarName + Ch
        else
          Sb.Append(Ch);
      end;

      Inc(I);
    end;

    if InPercent then
      Sb.Append('%' + VarName);
    if InExclamation then
      Sb.Append('!' + VarName);

    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function ParseCommandLine(const ACommandLine: string; const ASession: TSession): TParsedCommandLine;
var
  Expanded: string;
  I, Len: Integer;
  InQuote: Boolean;
  CurrToken: string;
  Tokens: TStringList;
  Ch, NextCh: Char;
  CmdLineList: TParsedCommandLine;
  Cmd: TParsedCommand;

  procedure InitParsedCommand(out ACmd: TParsedCommand);
  begin
    ACmd.ProgramName := '';
    ACmd.Args := TStringList.Create;
    ACmd.RedirInput := '';
    ACmd.RedirOutput := '';
    ACmd.RedirAppend := False;
    ACmd.RedirStderr := '';
    ACmd.PipeToNext := False;
    ACmd.OpAnd := False;
    ACmd.OpOr := False;
    ACmd.OpSeq := False;
  end;

var
  TIdx: Integer;
  Tok, NextTok: string;
begin
  Expanded := ExpandVariables(ACommandLine, ASession);
  Tokens := TStringList.Create;
  CmdLineList := TParsedCommandLine.Create;

  try
    InQuote := False;
    CurrToken := '';
    I := 1;
    Len := Length(Expanded);

    while I <= Len do
    begin
      Ch := Expanded[I];
      if I < Len then NextCh := Expanded[I + 1] else NextCh := #0;

      if Ch = '"' then
      begin
        InQuote := not InQuote;
        CurrToken := CurrToken + Ch;
      end
      else if (not InQuote) and (Ch in [' ', #9]) then
      begin
        if CurrToken <> '' then
        begin
          Tokens.Add(CurrToken);
          CurrToken := '';
        end;
      end
      else if (not InQuote) and (Ch in ['|', '<', '>', '&']) then
      begin
        if CurrToken <> '' then
        begin
          Tokens.Add(CurrToken);
          CurrToken := '';
        end;

        if (Ch = '>') and (NextCh = '>') then
        begin
          Tokens.Add('>>');
          Inc(I);
        end;

        if (Ch = '&') and (NextCh = '&') then
        begin
          Tokens.Add('&&');
          Inc(I);
        end;

        if (Ch = '|') and (NextCh = '|') then
        begin
          Tokens.Add('||');
          Inc(I);
        end
        else
          Tokens.Add(Ch);
      end;

      Inc(I);
    end;

    if CurrToken <> '' then
      Tokens.Add(CurrToken);

    InitParsedCommand(Cmd);
    TIdx := 0;

    while TIdx < Tokens.Count do
    begin
      Tok := Tokens[TIdx];
      if TIdx < Tokens.Count - 1 then NextTok := Tokens[TIdx + 1] else NextTok := '';

      if Tok = '|' then
      begin
        Cmd.PipeToNext := True;
        CmdLineList.Add(Cmd);
        InitParsedCommand(Cmd);
      end
      else if Tok = '&&' then
      begin
        Cmd.OpAnd := True;
        CmdLineList.Add(Cmd);
        InitParsedCommand(Cmd);
      end
      else if Tok = '||' then
      begin
        Cmd.OpOr := True;
        CmdLineList.Add(Cmd);
        InitParsedCommand(Cmd);
      end
      else if Tok = '&' then
      begin
        Cmd.OpSeq := True;
        CmdLineList.Add(Cmd);
        InitParsedCommand(Cmd);
      end
      else if Tok = '<' then
      begin
        Cmd.RedirInput := NextTok;
        Inc(TIdx);
      end
      else if Tok = '>' then
      begin
        Cmd.RedirOutput := NextTok;
        Cmd.RedirAppend := False;
        Inc(TIdx);
      end
      else if Tok = '>>' then
      begin
        Cmd.RedirOutput := NextTok;
        Cmd.RedirAppend := True;
        Inc(TIdx);
      end
      else if Tok = '2>' then
      begin
        Cmd.RedirStderr := NextTok;
        Inc(TIdx);
      end
      else
      begin
        if Cmd.ProgramName = '' then
          Cmd.ProgramName := Tok
        else
          Cmd.Args.Add(Tok);
      end;

      Inc(TIdx);
    end;

    if (Cmd.ProgramName <> '') or (Cmd.Args.Count > 0) then
      CmdLineList.Add(Cmd)
    else
      FreeAndNil(Cmd.Args);

    Result := CmdLineList;
  finally
    Tokens.Free;
  end;
end;

procedure FreeParsedCommandLine(ACmdLine: TParsedCommandLine);
var
  I: Integer;
  Cmd: TParsedCommand;
begin
  if Assigned(ACmdLine) then
  begin
    for I := 0 to ACmdLine.Count - 1 do
    begin
      Cmd := ACmdLine[I];
      if Assigned(Cmd.Args) then
        Cmd.Args.Free;
    end;
    ACmdLine.Free;
  end;
end;

end.
