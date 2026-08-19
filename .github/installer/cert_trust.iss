

;
; Appended to a working copy of Installer/Sandboxie-Plus.iss by
; .github/workflows/release.yml. The file in the repository is never modified.
;
; SbieDrv.sys is signed with a self-issued certificate, so Windows refuses to
; load it until that certificate is trusted. Rather than making the user run
; certutil by hand, the installer offers to do it through the "TrustCert" task.
; {#MyCertThumbprint} is defined by the workflow from the certificate that
; actually signed this build.
;

function NtQuerySystemInformation(SystemInformationClass: Cardinal;
  var SystemInformation: Cardinal; SystemInformationLength: Cardinal;
  ReturnLength: Cardinal): Cardinal;
  external 'NtQuerySystemInformation@ntdll.dll stdcall';

// True when the system was booted with test signing enabled. Mirrors
// MyIsTestSigning() in Sandboxie/core/drv/util.c: SystemCodeIntegrityInformation
// is class 103 and CODEINTEGRITY_OPTION_TESTSIGN is 0x2. Assume it is on when
// the query fails, so a quirk here cannot produce a spurious warning.
function IsTestSigningOn(): Boolean;
var
  Info: array[0..1] of Cardinal;
begin
  Info[0] := 8;
  Info[1] := 0;
  Result := True;

  if NtQuerySystemInformation(103, Info[0], 8, 0) = 0 then
    Result := (Info[1] and $2) <> 0;
end;

// certutil exits non-zero when the certificate is not in the store.
function IsCertTrusted(): Boolean;
var
  ExecRet: Integer;
begin
  Result := Exec(ExpandConstant('{sys}\certutil.exe'),
                 '-verifystore Root {#MyCertThumbprint}', '',
                 SW_HIDE, ewWaitUntilTerminated, ExecRet) and (ExecRet = 0);
end;

// Only offer the task when it would actually change something. A portable
// install does not load the driver, so it needs no certificate either.
function ShouldTrustCert(): Boolean;
begin
  Result := (not IsPortable) and (not IsCertTrusted);
end;

procedure CurPageChanged(CurPageID: Integer);
var
  NL: String;
begin
  // No line here may start with '#': the Inno preprocessor would read it as a
  // directive, so newlines go through NL rather than inline #13#10.
  NL := Chr(13) + Chr(10);

  if (CurPageID = wpReady) and (not IsPortable) and (not IsTestSigningOn) then
    SuppressibleMsgBox(
      'Test signing is not enabled on this system.' + NL + NL +
      'The Sandboxie driver is signed with a self-issued certificate, so Windows will ' +
      'refuse to load it until the system is booted with test signing enabled. The ' +
      'installation will finish, but the driver and the Sandboxie service will not start.' +
      NL + NL +
      'To enable it, run this in an elevated Command Prompt and reboot:' + NL + NL +
      '    bcdedit /set testsigning on' + NL + NL +
      'Secure Boot must be turned off in UEFI first, otherwise that command is refused. ' +
      'Memory Integrity (Windows Security > Device security > Core isolation) must be ' +
      'off as well.',
      mbInformation, MB_OK, MB_OK);
end;


[UninstallRun]
; Remove the certificate that this installer added to the machine stores.
Filename: "{sys}\certutil.exe"; Parameters: "-delstore Root {#MyCertThumbprint}"; Flags: runhidden; RunOnceId: "SbieDelCertRoot"
Filename: "{sys}\certutil.exe"; Parameters: "-delstore TrustedPublisher {#MyCertThumbprint}"; Flags: runhidden; RunOnceId: "SbieDelCertPub"
