unit CmdX2Config;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

// Per Plan v5 §1.3: TOML configuration removed. Registry is authoritative.
// This unit is retained only as a stub to keep the .dpr compiling until
// callers are migrated.

procedure LoadAllConfigs(ASession: TSession; const APath: string = '');

implementation

uses CmdX2Types;

procedure LoadAllConfigs(ASession: TSession; const APath: string);
begin
  // No-op: registry is the sole configuration source.
end;

end.