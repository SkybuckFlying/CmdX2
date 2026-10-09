unit CmdX2Config;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, CmdX2Types;

function GetGlobalConfigPath: string;
function GetMachineConfigPath: string;
function GetProjectConfigPath: string;

procedure LoadTOMLFile(const AFileName: string; var AConfig: TConfig; ASourceFile: string; var ASession: TSession);
procedure LoadAllConfigs(var ASession: TSession; const ASessionConfigPath: string = '');
procedure ImportRegistryPath(var ASession: TSession);
procedure SavePathToConfig(const ASession: TSession; const AFileName: string);

implementation

function CombinePaths(const Path1, Path2: string): string;
begin
  if Path1 = '' then
    Result := Path2
  else if Path2 = '' then
    Result := Path1
  else
    Result := IncludeTrailingPathDelimiter(Path1) + Path2;
end;

function GetGlobalConfigPath: string;
var
  AppData: string;
begin
  AppData := GetEnvironmentVariable('APPDATA');
  if AppData = '' then
    AppData := GetEnvironmentVariable('HOME');
  if AppData = '' then
    AppData := '.';
  Result := CombinePaths(AppData, 'CmdX2' + PathDelim + 'config.toml');
end;

function GetMachineConfigPath: string;
var
  ProgramData: string;
begin
  ProgramData := GetEnvironmentVariable('PROGRAMDATA');
  if ProgramData = '' then
    ProgramData := '/etc';
  Result := CombinePaths(ProgramData, 'CmdX2' + PathDelim + 'config.toml');
end;

function GetProjectConfigPath: string;
begin
  Result := CombinePaths(GetCurrentDir, '.cmdx2' + PathDelim + 'config.toml');
end;

procedure ParseTOMLContent(const AContent: string; var AConfig: TConfig; const ASourceFile: string; var ASession: TSession);
var
  Lines: TStringList;
  I: Integer;
  Line, Trimmed, CurrentSection, Key, Value: string;
  InEntries: Boolean;
  EntrySource: TPathEntrySource;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AContent;
    CurrentSection := '';
    InEntries := False;

    for I := 0 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      Trimmed := Trim(Line);

      if (Trimmed = '') or (Trimmed[1] = '#') or (Trimmed[1] = ';') then
        Continue;

      if (Trimmed[1] = '[') and (Trimmed[Length(Trimmed)] = ']') then
      begin
        CurrentSection := LowerCase(Copy(Trimmed, 2, Length(Trimmed) - 2));
        InEntries := False;
        Continue;
      end;

      if InEntries then
      begin
        if Pos(']', Trimmed) > 0 then
        begin
          InEntries := False;
          Continue;
        end;
        Value := Trimmed;
        if (Length(Value) > 0) and (Value[Length(Value)] = ',') then
          Value := Trim(Copy(Value, 1, Length(Value) - 1));
        if (Length(Value) >= 2) and ((Value[1] = '"') or (Value[1] = '''')) then
          Value := Copy(Value, 2, Length(Value) - 2);

        if Value <> '' then
        begin
          EntrySource.Path := Value;
          EntrySource.SourceFile := ASourceFile;
          EntrySource.Priority := 2;
          ASession.PathEntries.Add(EntrySource);
        end;
        Continue;
      end;

      if Pos('=', Trimmed) > 0 then
      begin
        Key := LowerCase(Trim(Copy(Trimmed, 1, Pos('=', Trimmed) - 1)));
        Value := Trim(Copy(Trimmed, Pos('=', Trimmed) + 1, Length(Trimmed)));

        if CurrentSection = 'path' then
        begin
          if Key = 'append_system' then
            AConfig.PathConfig.AppendSystem := SameText(Value, 'true')
          else if Key = 'deduplicate' then
            AConfig.PathConfig.Deduplicate := SameText(Value, 'true')
          else if Key = 'normalize' then
            AConfig.PathConfig.Normalize := SameText(Value, 'true')
          else if Key = 'entries' then
          begin
            if Pos('[', Value) > 0 then
            begin
              if Pos(']', Value) = 0 then
                InEntries := True;
            end;
          end;
        end
        else if CurrentSection = 'probe' then
        begin
          if Key = 'enabled' then
            AConfig.ProbeConfig.Enabled := SameText(Value, 'true')
          else if Key = 'cached_ceiling' then
            AConfig.ProbeConfig.CachedCeiling := StrToInt64Def(Value, 0);
        end;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

procedure LoadTOMLFile(const AFileName: string; var AConfig: TConfig; ASourceFile: string; var ASession: TSession);
var
  SL: TStringList;
begin
  if FileExists(AFileName) then
  begin
    SL := TStringList.Create;
    try
      SL.LoadFromFile(AFileName);
      ParseTOMLContent(SL.Text, AConfig, AFileName, ASession);
    except
      on E: Exception do
        Writeln(ErrOutput, 'Error reading config file ', AFileName, ': ', E.Message);
    end;
    SL.Free;
  end;
end;

procedure LoadAllConfigs(var ASession: TSession; const ASessionConfigPath: string = '');
begin
  ASession.PathEntries.Clear;

  if (ASessionConfigPath <> '') and FileExists(ASessionConfigPath) then
    LoadTOMLFile(ASessionConfigPath, ASession.Config, ASessionConfigPath, ASession);

  LoadTOMLFile(GetProjectConfigPath, ASession.Config, GetProjectConfigPath, ASession);
  LoadTOMLFile(GetMachineConfigPath, ASession.Config, GetMachineConfigPath, ASession);
  LoadTOMLFile(GetGlobalConfigPath, ASession.Config, GetGlobalConfigPath, ASession);
end;

procedure ImportRegistryPath(var ASession: TSession);
var
  SysPath, CombinedPath, CurrPart: string;
  I, StartIdx: Integer;
  EntrySource: TPathEntrySource;
begin
  SysPath := GetEnvironmentVariable('PATH');
  CombinedPath := SysPath;

  StartIdx := 1;
  for I := 1 to Length(CombinedPath) do
  begin
    if CombinedPath[I] = ';' then
    begin
      CurrPart := Trim(Copy(CombinedPath, StartIdx, I - StartIdx));
      if CurrPart <> '' then
      begin
        EntrySource.Path := CurrPart;
        EntrySource.SourceFile := 'RegistryImport';
        EntrySource.Priority := 4;
        ASession.PathEntries.Add(EntrySource);
      end;
      StartIdx := I + 1;
    end;
  end;

  if StartIdx <= Length(CombinedPath) then
  begin
    CurrPart := Trim(Copy(CombinedPath, StartIdx, Length(CombinedPath) - StartIdx + 1));
    if CurrPart <> '' then
    begin
      EntrySource.Path := CurrPart;
      EntrySource.SourceFile := 'RegistryImport';
      EntrySource.Priority := 4;
      ASession.PathEntries.Add(EntrySource);
    end;
  end;
end;

procedure SavePathToConfig(const ASession: TSession; const AFileName: string);
var
  Lines: TStringList;
  I: Integer;
  Dir: string;
begin
  Dir := ExtractFilePath(AFileName);
  if (Dir <> '') and not DirectoryExists(Dir) then
    ForceDirectories(Dir);

  Lines := TStringList.Create;
  try
    Lines.Add('[path]');
    Lines.Add('entries = [');
    for I := 0 to ASession.PathEntries.Count - 1 do
    begin
      Lines.Add('  "' + ASession.PathEntries[I].Path + '",');
    end;
    Lines.Add(']');
    Lines.Add('append_system = true');
    Lines.Add('deduplicate = true');
    Lines.Add('normalize = true');
    Lines.Add('');
    Lines.Add('[pathext]');
    Lines.Add('extensions = [".COM", ".EXE", ".BAT", ".CMD", ".PS1", ".VBS"]');
    Lines.Add('');
    Lines.Add('[probe]');
    Lines.Add('enabled = ' + LowerCase(BoolToStr(ASession.Config.ProbeConfig.Enabled, True)));
    Lines.Add('cached_ceiling = ' + IntToStr(ASession.Limits.MeasuredCeiling));

    Lines.SaveToFile(AFileName);
  finally
    Lines.Free;
  end;
end;

end.
