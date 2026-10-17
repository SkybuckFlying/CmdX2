unit CmdX2Parser;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections, CmdX2Types;

type
  TTokenKind = (
    tkWord,
    tkRedirectOut, tkRedirectOutAppend,
    tkRedirectIn,
    tkRedirectErr, tkRedirectErrAppend,
    tkRedirectDupOut, tkRedirectDupErr,
    tkPipe, tkAnd, tkOr, tkSeq,
    tkLParen, tkRParen
  );

  TToken = record
    Kind: TTokenKind;
    Text: string;
  end;

  TTokenList = TList<TToken>;

  TRedirectSource = (rsDefault, rsStdin, rsStdout, rsStderr);
  TRedirectOpKind = (roToFile, roFromFile, roToNul, roDup);

  TRedirectOp = record
    Source: TRedirectSource;
    Kind: TRedirectOpKind;
    Append: Boolean;
    Target: string;
  end;

  TOperator = (opNone, opAnd, opOr, opSeq);

  TParsedCommand = class
  public
    ProgramName: string;
    Args: TStringList;
    Redirects: TList<TRedirectOp>;
    PipeToNext: Boolean;
    Op: TOperator;
    constructor Create;
    destructor Destroy; override;
  end;

  TParsedCommandLine = class(TObjectList<TParsedCommand>);

function Tokenize(const AInput: string): TTokenList;
function ParseSimple(const ATokens: TTokenList): TParsedCommandLine;
function ParseCommandLine(const ACommandLine: string; ASession: TSession): TParsedCommandLine;
function ExpandVariables(const AInput: string; ASession: TSession): string;

implementation

function MakeToken(Kind: TTokenKind; const Text: string): TToken;
begin
  Result.Kind := Kind;
  Result.Text := Text;
end;

function Tokenize(const AInput: string): TTokenList;
var
  I, Len: Integer;
  Ch: Char;
  InQuote: Boolean;
  CurrToken: string;

  procedure FlushWord;
  begin
    if CurrToken <> '' then
    begin
      Result.Add(MakeToken(tkWord, CurrToken));
      CurrToken := '';
    end;
  end;

begin
  Result := TTokenList.Create;
  InQuote := False;
  CurrToken := '';
  I := 1;
  Len := Length(AInput);

  while I <= Len do
  begin
    Ch := AInput[I];

    if (Ch = '^') and (not InQuote) then
    begin
      Inc(I);
      if I <= Len then
      begin
        CurrToken := CurrToken + AInput[I];
        Inc(I);
      end;
      Continue;
    end;

    if Ch = '"' then
    begin
      InQuote := not InQuote;
      CurrToken := CurrToken + Ch;
      Inc(I);
      Continue;
    end;

    if InQuote then
    begin
      CurrToken := CurrToken + Ch;
      Inc(I);
      Continue;
    end;

    if (Ch = ' ') or (Ch = #9) then
    begin
      FlushWord;
      Inc(I);
      Continue;
    end;

    if Ch = '(' then
    begin
      FlushWord;
      Result.Add(MakeToken(tkLParen, ''));
      Inc(I);
      Continue;
    end;
    if Ch = ')' then
    begin
      FlushWord;
      Result.Add(MakeToken(tkRParen, ''));
      Inc(I);
      Continue;
    end;

    if (Ch = '2') and (I + 1 <= Len) and (AInput[I + 1] = '>') then
    begin
      FlushWord;
      if (I + 2 <= Len) and (AInput[I + 2] = '&') then
      begin
        Result.Add(MakeToken(tkRedirectDupErr, ''));
        Inc(I, 3);
      end
      else if (I + 2 <= Len) and (AInput[I + 2] = '>') then
      begin
        Result.Add(MakeToken(tkRedirectErrAppend, ''));
        Inc(I, 3);
      end
      else
      begin
        Result.Add(MakeToken(tkRedirectErr, ''));
        Inc(I, 2);
      end;
      Continue;
    end;

    if (Ch = '1') and (I + 1 <= Len) and (AInput[I + 1] = '>') then
    begin
      FlushWord;
      if (I + 2 <= Len) and (AInput[I + 2] = '&') then
      begin
        Result.Add(MakeToken(tkRedirectDupOut, ''));
        Inc(I, 3);
      end
      else if (I + 2 <= Len) and (AInput[I + 2] = '>') then
      begin
        Result.Add(MakeToken(tkRedirectOutAppend, ''));
        Inc(I, 3);
      end
      else
      begin
        Result.Add(MakeToken(tkRedirectOut, ''));
        Inc(I, 2);
      end;
      Continue;
    end;

    if Ch = '>' then
    begin
      FlushWord;
      if (I + 1 <= Len) and (AInput[I + 1] = '>') then
      begin
        Result.Add(MakeToken(tkRedirectOutAppend, ''));
        Inc(I, 2);
      end
      else if (I + 1 <= Len) and (AInput[I + 1] = '&') then
      begin
        Result.Add(MakeToken(tkRedirectDupOut, ''));
        Inc(I, 2);
      end
      else
      begin
        Result.Add(MakeToken(tkRedirectOut, ''));
        Inc(I);
      end;
      Continue;
    end;

    if Ch = '<' then
    begin
      FlushWord;
      Result.Add(MakeToken(tkRedirectIn, ''));
      Inc(I);
      Continue;
    end;

    if Ch = '|' then
    begin
      FlushWord;
      if (I + 1 <= Len) and (AInput[I + 1] = '|') then
      begin
        Result.Add(MakeToken(tkOr, ''));
        Inc(I, 2);
      end
      else
      begin
        Result.Add(MakeToken(tkPipe, ''));
        Inc(I);
      end;
      Continue;
    end;

    if Ch = '&' then
    begin
      FlushWord;
      if (I + 1 <= Len) and (AInput[I + 1] = '&') then
      begin
        Result.Add(MakeToken(tkAnd, ''));
        Inc(I, 2);
      end
      else
      begin
        Result.Add(MakeToken(tkSeq, ''));
        Inc(I);
      end;
      Continue;
    end;

    CurrToken := CurrToken + Ch;
    Inc(I);
  end;

  FlushWord;
end;

function NextWord(ATokens: TTokenList; var I: Integer): string;
begin
  Result := '';
  Inc(I);
  if I < ATokens.Count then
    if ATokens[I].Kind = tkWord then
      Result := ATokens[I].Text;
end;

function ParseSimple(const ATokens: TTokenList): TParsedCommandLine;
var
  I: Integer;
  Cmd: TParsedCommand;
  Tok: TToken;
  Target: string;
  Append: Boolean;
  Source: TRedirectSource;
  Op: TRedirectOp;
begin
  Result := TParsedCommandLine.Create;
  Cmd := nil;
  I := 0;

  while I < ATokens.Count do
  begin
    Tok := ATokens[I];
    case Tok.Kind of
      tkWord:
        begin
          if Cmd = nil then Cmd := TParsedCommand.Create;
          if Cmd.ProgramName = '' then
            Cmd.ProgramName := Tok.Text
          else
            Cmd.Args.Add(Tok.Text);
          Inc(I);
        end;
      tkRedirectOut, tkRedirectOutAppend,
      tkRedirectErr, tkRedirectErrAppend:
        begin
          if Cmd = nil then Cmd := TParsedCommand.Create;
          Append := (Tok.Kind = tkRedirectOutAppend) or (Tok.Kind = tkRedirectErrAppend);
          if (Tok.Kind = tkRedirectErr) or (Tok.Kind = tkRedirectErrAppend) then
            Source := rsStderr
          else
            Source := rsStdout;
          Target := NextWord(ATokens, I);
          Op.Source := Source;
          Op.Append := Append;
          if SameText(Target, 'nul') then
          begin
            Op.Kind := roToNul;
            Op.Target := '';
          end
          else
          begin
            Op.Kind := roToFile;
            Op.Target := Target;
          end;
          Cmd.Redirects.Add(Op);
        end;
      tkRedirectIn:
        begin
          if Cmd = nil then Cmd := TParsedCommand.Create;
          Target := NextWord(ATokens, I);
          Op.Source := rsStdin;
          Op.Kind := roFromFile;
          Op.Append := False;
          Op.Target := Target;
          Cmd.Redirects.Add(Op);
        end;
      tkRedirectDupOut, tkRedirectDupErr:
        begin
          if Cmd = nil then Cmd := TParsedCommand.Create;
          if Tok.Kind = tkRedirectDupErr then
            Source := rsStderr
          else
            Source := rsStdout;
          Target := NextWord(ATokens, I);
          if (Target = '1') or (Target = '2') then
          begin
            Op.Source := Source;
            Op.Kind := roDup;
            Op.Append := False;
            Op.Target := Target;
            Cmd.Redirects.Add(Op);
          end;
        end;
      tkPipe:
        begin
          if Cmd <> nil then
          begin
            Cmd.PipeToNext := True;
            Result.Add(Cmd);
            Cmd := nil;
          end;
          Inc(I);
        end;
      tkAnd, tkOr, tkSeq:
        begin
          if Cmd <> nil then
          begin
            case Tok.Kind of
              tkAnd: Cmd.Op := opAnd;
              tkOr: Cmd.Op := opOr;
              tkSeq: Cmd.Op := opSeq;
            end;
            Result.Add(Cmd);
            Cmd := nil;
          end;
          Inc(I);
        end;
    else
      Inc(I);
    end;
  end;

  if Cmd <> nil then Result.Add(Cmd);
end;

function ExpandVariables(const AInput: string; ASession: TSession): string;
var
  I, Len: Integer;
  InPercent: Boolean;
  VarName, Val: string;
  Sb: TStringBuilder;
  Ch: Char;
begin
  Sb := TStringBuilder.Create;
  try
    I := 1;
    Len := Length(AInput);
    InPercent := False;
    VarName := '';

    while I <= Len do
    begin
      Ch := AInput[I];
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
      else if InPercent then
        VarName := VarName + Ch
      else
        Sb.Append(Ch);
      Inc(I);
    end;

    if InPercent then
      Sb.Append('%' + VarName);

    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function ParseCommandLine(const ACommandLine: string; ASession: TSession): TParsedCommandLine;
var
  Expanded: string;
  Toks: TTokenList;
begin
  Expanded := ExpandVariables(ACommandLine, ASession);
  Toks := Tokenize(Expanded);
  try
    Result := ParseSimple(Toks);
  finally
    Toks.Free;
  end;
end;

constructor TParsedCommand.Create;
begin
  inherited Create;
  Args := TStringList.Create;
  Redirects := TList<TRedirectOp>.Create;
  PipeToNext := False;
  Op := opNone;
end;

destructor TParsedCommand.Destroy;
begin
  Args.Free;
  Redirects.Free;
  inherited;
end;

end.