program TestCmdX2;

{$APPTYPE CONSOLE}
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

uses
  SysUtils, Classes, Generics.Collections, Windows,
  CmdX2Types, CmdX2Exec, CmdX2Parser, CmdX2Path;

var
  Passed, Failed: Integer;

procedure Check(const ATestName: string; ACondition: Boolean);
begin
  if ACondition then
  begin
    Writeln('[PASS] ', ATestName);
    Inc(Passed);
  end
  else
  begin
    Writeln('[FAIL] ', ATestName);
    Inc(Failed);
  end;
end;

procedure TestComparer;
var
  Env: TEnvironmentMap;
begin
  Env := NewEnvironmentMap;
  try
    Env.AddOrSetValue('PATH', 'a');
    Env.AddOrSetValue('Path', 'b');
    Env.AddOrSetValue('path', 'c');
    Check('Case-insensitive env map (3 entries collapse to 1)', Env.Count = 1);
    Check('Last write wins', Env['PATH'] = 'c');
  finally
    Env.Free;
  end;
end;

procedure TestTokenizer;
var
  Toks: TTokenList;
begin
  Toks := Tokenize('echo hello');
  try
    Check('echo hello -> 2 words', (Toks.Count = 2)
      and (Toks[0].Kind = tkWord) and (Toks[0].Text = 'echo'));
  finally
    Toks.Free;
  end;

  Toks := Tokenize('echo a 2>&1');
  try
    Check('2>&1 tokenized',
      (Toks.Count = 4)
      and (Toks[2].Kind = tkRedirectDupErr)
      and (Toks[3].Text = '1'));
  finally
    Toks.Free;
  end;

  Toks := Tokenize('echo a 1>&2');
  try
    Check('1>&2 tokenized',
      (Toks.Count = 4)
      and (Toks[2].Kind = tkRedirectDupOut)
      and (Toks[3].Text = '2'));
  finally
    Toks.Free;
  end;

  Toks := Tokenize('a&&b');
  try
    Check('a&&b gives 3 tokens',
      (Toks.Count = 3)
      and (Toks[1].Kind = tkAnd)
      and (Toks[0].Text = 'a') and (Toks[2].Text = 'b'));
  finally
    Toks.Free;
  end;

  Toks := Tokenize('a^&b');
  try
    Check('a^&b is one word a&b',
      (Toks.Count = 1) and (Toks[0].Text = 'a&b'));
  finally
    Toks.Free;
  end;
end;

procedure TestQuoteArg;
begin
  Check('QuoteArg empty -> ""', WinQuoteArg('') = '""');
  Check('QuoteArg simple', WinQuoteArg('abc') = 'abc');
  Check('QuoteArg with space', WinQuoteArg('a b') = '"a b"');
  Check('QuoteArg trailing slash', WinQuoteArg('a b\') = '"a b\\"');
end;

procedure TestRebuildPath;
var
  S: TSession;
begin
  S := TSession.Create;
  try
    S.Environment.AddOrSetValue('PATH', 'C:\A;C:\B;C:\C');
    RebuildPathEntries(S);
    Check('RebuildPathEntries gives 3 entries', S.PathEntries.Count = 3);
    Check('RawPath set', S.RawPath = 'C:\A;C:\B;C:\C');
  finally
    S.Free;
  end;
end;

begin
  Passed := 0;
  Failed := 0;
  Writeln('=== CmdX2 Milestone A Tests ===');
  TestComparer;
  TestTokenizer;
  TestQuoteArg;
  TestRebuildPath;
  Writeln;
  Writeln(Format('Summary: %d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1) else Halt(0);
end.