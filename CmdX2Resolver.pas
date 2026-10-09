unit CmdX2Resolver;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, CmdX2Types;

function ResolveCommand(var ASession: TSession; const ACmdName: string;
  out AResolvedPath, AMatchedExt: string; out APathIndex: Integer): Boolean;
function IsBuiltInCommand(const ACmdName: string): Boolean;

implementation

function IsBuiltInCommand(const ACmdName: string): Boolean;
var
  Cmd: string;
begin
  Cmd := LowerCase(Trim(ACmdName));
  Result := (Cmd = 'dir') or (Cmd = 'cd') or (Cmd = 'chdir') or (Cmd = 'md') or (Cmd = 'mkdir') or
            (Cmd = 'rd') or (Cmd = 'rmdir') or (Cmd = 'del') or (Cmd = 'erase') or (Cmd = 'copy') or
            (Cmd = 'xcopy') or (Cmd = 'move') or (Cmd = 'ren') or (Cmd = 'rename') or (Cmd = 'type') or
            (Cmd = 'more') or (Cmd = 'set') or (Cmd = 'path') or (Cmd = 'prompt') or (Cmd = 'title') or
            (Cmd = 'color') or (Cmd = 'cls') or (Cmd = 'ver') or (Cmd = 'vol') or (Cmd = 'date') or
            (Cmd = 'time') or (Cmd = 'pause') or (Cmd = 'exit') or (Cmd = 'echo') or (Cmd = 'shift') or
            (Cmd = 'call') or (Cmd = 'goto') or (Cmd = 'start') or (Cmd = 'assoc') or (Cmd = 'ftype') or
            (Cmd = 'setlocal') or (Cmd = 'endlocal') or (Cmd = 'pushd') or (Cmd = 'popd') or (Cmd = 'if') or
            (Cmd = 'else') or (Cmd = 'for') or (Cmd = 'rem') or (Cmd = '::') or
            (Cmd = 'cmdx2');
end;

function FileExistsCaseInsensitive(const APath: string): Boolean;
begin
  Result := FileExists(APath);
end;

function TryPathWithExtensions(const ABasePath: string; const AExtensions: TStringList;
  out AMatchedPath, AMatchedExt: string): Boolean;
var
  I: Integer;
  Ext, Candidate: string;
begin
  Result := False;
  AMatchedPath := '';
  AMatchedExt := '';

  if FileExistsCaseInsensitive(ABasePath) and (not DirectoryExists(ABasePath)) then
  begin
    AMatchedPath := ABasePath;
    AMatchedExt := ExtractFileExt(ABasePath);
    Exit(True);
  end;

  for I := 0 to AExtensions.Count - 1 do
  begin
    Ext := AExtensions[I];
    if (Ext <> '') and (Ext[1] <> '.') then
      Ext := '.' + Ext;

    Candidate := ABasePath + Ext;
    if FileExistsCaseInsensitive(Candidate) and (not DirectoryExists(Candidate)) then
    begin
      AMatchedPath := Candidate;
      AMatchedExt := Ext;
      Exit(True);
    end;
  end;
end;

function CombinePath(const Dir, Name: string): string;
begin
  if Dir = '' then
    Result := Name
  else
    Result := IncludeTrailingPathDelimiter(Dir) + Name;
end;

function ResolveCommand(var ASession: TSession; const ACmdName: string;
  out AResolvedPath, AMatchedExt: string; out APathIndex: Integer): Boolean;
var
  I: Integer;
  CleanCmd, CandidateBase, MatchedFile, Ext: string;
  Entry: TPathEntrySource;
begin
  Result := False;
  AResolvedPath := '';
  AMatchedExt := '';
  APathIndex := -1;

  CleanCmd := Trim(ACmdName);
  if CleanCmd = '' then
    Exit;

  if ASession.ResolverCache.TryGetValue(LowerCase(CleanCmd), AResolvedPath) then
  begin
    if FileExistsCaseInsensitive(AResolvedPath) then
    begin
      AMatchedExt := ExtractFileExt(AResolvedPath);
      Exit(True);
    end
    else
      ASession.ResolverCache.Remove(LowerCase(CleanCmd));
  end;

  if (Pos('\', CleanCmd) > 0) or (Pos('/', CleanCmd) > 0) or
     ((Length(CleanCmd) >= 2) and (CleanCmd[2] = ':')) then
  begin
    CandidateBase := ExpandFileName(CleanCmd);
    if TryPathWithExtensions(CandidateBase, ASession.Config.PathextConfig.Extensions, MatchedFile, Ext) then
    begin
      AResolvedPath := MatchedFile;
      AMatchedExt := Ext;
      APathIndex := -1;
      ASession.ResolverCache.AddOrSetValue(LowerCase(CleanCmd), AResolvedPath);
      Exit(True);
    end;
    Exit(False);
  end;

  if (Copy(CleanCmd, 1, 2) = './') or (Copy(CleanCmd, 1, 2) = '.\') then
  begin
    CandidateBase := ExpandFileName(CleanCmd);
    if TryPathWithExtensions(CandidateBase, ASession.Config.PathextConfig.Extensions, MatchedFile, Ext) then
    begin
      AResolvedPath := MatchedFile;
      AMatchedExt := Ext;
      APathIndex := -1;
      ASession.ResolverCache.AddOrSetValue(LowerCase(CleanCmd), AResolvedPath);
      Exit(True);
    end;
    Exit(False);
  end;

  for I := 0 to ASession.PathEntries.Count - 1 do
  begin
    Entry := ASession.PathEntries[I];
    CandidateBase := CombinePath(Entry.Path, CleanCmd);

    if TryPathWithExtensions(CandidateBase, ASession.Config.PathextConfig.Extensions, MatchedFile, Ext) then
    begin
      AResolvedPath := MatchedFile;
      AMatchedExt := Ext;
      APathIndex := I;
      ASession.UsedEntries.AddOrSetValue(Entry.Path, True);
      ASession.ResolverCache.AddOrSetValue(LowerCase(CleanCmd), AResolvedPath);
      Exit(True);
    end;
  end;
end;

end.
