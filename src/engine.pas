unit engine;

interface

uses
  Windows, SysUtils, Classes;

type
(*  PBinaryEntry = ^TBinaryEntry;
  TBinaryEntry = record
    StrRawOffset: LongWord;
    StrPtrOffset: LongWord;
    Str: string;
    SectionName: string;
  end;*)

  TXbeStringsExtractor = class
  private
    fXbeStream: TMemoryStream;
//    fExtractedStrings: TList;
(*    procedure Add(StrPtrOffset, StrRawOffset: LongWord; Str,
      SectionName: string); *)
//    procedure Clear;
    procedure FindOffset(var TextF: TextFile; StringPointerValue,
      StringRawOffset: LongWord; Str, SectionName: string);
    function IsValidChar(C: Char): Boolean;
    function RetrieveString(var NumRead: LongWord;
      const MinLength: Boolean): string;
    function IsNumeric(S: string): Boolean;
    property XbeStream: TMemoryStream read fXbeStream;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Execute(const XbeFileName, CsvOutputFileName: TFileName);
  end;
  
implementation

type
  _XBE_HEADER = packed record      // from DXBX
    dwMagic: array [0..3] of AnsiChar; // 0x0000 - magic number [should be "XBEH"]
    pbDigitalSignature: array [0..255] of Byte; // 0x0004 - digital signature
    dwBaseAddr: LongWord; // 0x0104 - base address
    dwSizeofHeaders: LongWord; // 0x0108 - size of headers
    dwSizeofImage: LongWord; // 0x010C - size of image
    dwSizeofImageHeader: LongWord; // 0x0110 - size of image header
    dwTimeDate: LongWord; // 0x0114 - timedate stamp
    dwCertificateAddr: LongWord; // 0x0118 - certificate address
    dwSections: LongWord; // 0x011C - number of sections
    dwSectionHeadersAddr: LongWord; // 0x0120 - section headers address
    dwInitFlags: array [0..3] of Byte; // 0x0124 - initialization flags
    dwEntryAddr: LongWord; // 0x0128 - entry point address
    dwTLSAddr: LongWord; // 0x012C - thread local storage directory address
    dwPeStackCommit: LongWord; // 0x0130 - size of stack commit
    dwPeHeapReserve: LongWord; // 0x0134 - size of heap reserve
    dwPeHeapCommit: LongWord; // 0x0138 - size of heap commit
    dwPeBaseAddr: LongWord; // 0x013C - original base address
    dwPeSizeofImage: LongWord; // 0x0140 - size of original image
    dwPeChecksum: LongWord; // 0x0144 - original checksum
    dwPeTimeDate: LongWord; // 0x0148 - original timedate stamp
    dwDebugPathNameAddr: LongWord; // 0x014C - debug pathname address
    dwDebugFileNameAddr: LongWord; // 0x0150 - debug FileName address
    dwDebugUnicodeFileNameAddr: LongWord; // 0x0154 - debug unicode FileName address
    dwKernelImageThunkAddr: LongWord; // 0x0158 - kernel image thunk address
    dwNonKernelImportDirAddr: LongWord; // 0x015C - non kernel import directory address
    dwLibraryVersions: LongWord; // 0x0160 - number of library versions
    dwLibraryVersionsAddr: LongWord; // 0x0164 - library versions address
    dwKernelLibraryVersionAddr: LongWord; // 0x0168 - kernel library version address
    dwXAPILibraryVersionAddr: LongWord; // 0x016C - xapi library version address
    dwLogoBitmapAddr: LongWord; // 0x0170 - logo bitmap address
    dwSizeofLogoBitmap: LongWord; // 0x0174 - logo bitmap size
  end;

  _XBE_SECTIONHEADER = packed record
  // Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:100
    dwFlags: array [0..3] of Byte;
    dwVirtualAddr: DWord; // virtual address
    dwVirtualSize: DWord; // virtual size
    dwRawAddr: DWord; // file offset to raw Data
    dwSizeofRaw: DWord; // size of raw Data
    dwSectionNameAddr: DWord; // section name addr
    dwSectionRefCount: DWord; // section reference count
    dwHeadSharedRefCountAddr: DWord; // head shared page reference count address
    dwTailSharedRefCountAddr: DWord; // tail shared page reference count address
    bzSectionDigest: array [0..19] of Byte; // section digest
  end;

{ TXbeStringsExtractor }

procedure TXbeStringsExtractor.Execute(const XbeFileName, CsvOutputFileName: TFileName);
var
  Header: _XBE_HEADER;
  Section: _XBE_SECTIONHEADER;
  i: Integer;
  StrLength, NextSectionHeaderOffset, SectionMaxOffset, StrRawOffset,
  StrPtrValue: LongWord;
  SectionName, StrBuf: string;
  FStream: TFileStream;
  TextF: TextFile;
//  Item: TBinaryEntry;
  
begin
  FStream := TFileStream.Create(XbeFileName, fmOpenRead);
  fXbeStream := TMemoryStream.Create;
  try
    XbeStream.CopyFrom(FStream, 0);
    XbeStream.Seek(0, soFromBeginning);
    XbeStream.Read(Header, SizeOf(_XBE_HEADER));
    XbeStream.Seek(Header.dwSectionHeadersAddr - Header.dwBaseAddr, soFromBeginning);

    AssignFile(TextF, CsvOutputFileName);
    ReWrite(TextF);

    WriteLn(TextF,
      '"String";"String Raw Offset";"String Pointer Offset";"String Raw Offset (Dec)";"String Pointer Offset (Dec)";"Section Name"');

    for i := 0 to Header.dwSections - 1 do begin
      // Read section header
      XbeStream.Read(Section, SizeOf(_XBE_SECTIONHEADER));
      NextSectionHeaderOffset := XbeStream.Position;

      // Retrieve section name
      XbeStream.Seek(Section.dwSectionNameAddr - Header.dwBaseAddr, soFromBeginning);
      SectionName := RetrieveString(StrLength, False);

      // Skipping...
      if (SectionName = '$$XTIMAGE') or (SectionName = 'D4_CODE')
        or (SectionName = '.text') or (SectionName = 'D12_CODE')
        or (SectionName = 'DOLBY') or (SectionName = 'DSOUND')
        or (SectionName = 'FTBL') or (SectionName = 'PSGSFD00')
        or (SectionName = 'PSGSFD_B') or (SectionName = 'PSGSFD_I')
        or (SectionName = 'PSGSFD_P') or (SectionName = 'XGRPH')
        or (SectionName = 'XPP') or (SectionName = 'D3_CODE') then begin
        WriteLn('SKIPPING "', SectionName, '"...');
        XbeStream.Seek(NextSectionHeaderOffset, soFromBeginning);
        Continue;
      end;


(*      if (SectionName <> '.rdata') then begin
        XbeStream.Seek(NextSectionHeaderOffset, soFromBeginning);
        Continue;
      end; *)

      WriteLn('Scanning "', SectionName, '"...');

      // Read the section content
      XbeStream.Seek(Section.dwRawAddr, soFromBeginning);
      SectionMaxOffset := Section.dwRawAddr + Section.dwSizeofRaw;
      repeat

        StrRawOffset := XbeStream.Position;
        StrBuf := RetrieveString(StrLength, True);
        if Length(StrBuf) > 2 then begin

          // if the string is valid, the string will be referenced by this value in the xbe
          StrPtrValue := Section.dwVirtualAddr + (StrRawOffset - Section.dwRawAddr);

          // Finding offset
          FindOffset(TextF, StrPtrValue, StrRawOffset, StrBuf, SectionName);

          // we continue
          XbeStream.Seek(StrRawOffset + StrLength, soFromBeginning);
        end;

        if (XbeStream.Position mod 2000) = 0 then
          WriteLn(XbeStream.Position, '/', SectionMaxOffset);
          
      until (XbeStream.Position >= XbeStream.Size) or (XbeStream.Position >= SectionMaxOffset);

      // Go to the next section
      XbeStream.Seek(NextSectionHeaderOffset, soFromBeginning);
    end; // Header.dwSections

(*    for i := 0 to fExtractedStrings.Count - 1 do begin
      Item := PBinaryEntry(fExtractedStrings[i])^;
      WriteLn(Item.StrRawOffset, ';', Item.StrPtrOffset, ';',
        Item.SectionName, ';', Item.Str);
    end; *)

    CloseFile(TextF);

  finally
    XbeStream.Free;
    FStream.Free;
  end;
end;

procedure TXbeStringsExtractor.FindOffset(var TextF: TextFile; StringPointerValue,
  StringRawOffset: LongWord; Str, SectionName: string);
var
  ReadValue, StrPtrOffset: LongWord;
  i: Integer;

begin
  for i := 0 to 3 do begin
    
    XbeStream.Seek(i, soFromBeginning);

    repeat
      StrPtrOffset := XbeStream.Position;
      XbeStream.Read(ReadValue, 4);

      if ReadValue = StringPointerValue then begin
        WriteLn(TextF,
          '"', Str, '"', ';',
          IntToHex(StringRawOffset, 8), ';',
          IntToHex(StrPtrOffset, 8), ';',
          StringRawOffset, ';',
          StrPtrOffset, ';',
          '"', SectionName, '"'
        );

        WriteLn(
          'ValueSearched=', IntToHex(StringPointerValue, 8), ', ',
          'StrPtrOffset=', IntToHex(StrPtrOffset, 8), ', ',
          'StrRawOffset=', IntToHex(StringRawOffset, 8), ', ',
          'Str="', Str, '"');
      end;

    until XbeStream.Position >= XbeStream.Size;

  end;
end;

// Caractères permettant de reconnaitre une string valide
function TXbeStringsExtractor.IsValidChar(C: Char): Boolean;
begin
  Result := C in [#$20..#$7C, #$A5, #$AE, #$BB, #$C2..#$C6, #$CA, #$CD, #$DE,
    #$DF, #$E1, #$E2];
end;

// IsNumeric
function TXbeStringsExtractor.IsNumeric(S: string): Boolean;
var
  E, Crap: Integer;
  
begin
  Val(Trim(S), Crap, E);
  Result := (E = 0);
end;

// RetrieveString
function TXbeStringsExtractor.RetrieveString(var NumRead: LongWord;
  const MinLength: Boolean): string;
const
  MIN_LENGTH = 3;

var
  C: Char;
  Done: Boolean;
  
begin
  Result := '';
  Done := False;
  
  // Check the first char
  NumRead := XbeStream.Read(C, 1);
  if not (C in [#$2E, #$20, #$30..#$39, #$40..#$5B, #$5F..#$7A]) then
    Exit;

  repeat
    // on double les '"' pour éviter des erreurs de séparateur
    if C = '"' then
      Result := Result + '"';

    if not Done then
      Result := Result + C;

    Inc(NumRead, XbeStream.Read(C, 1));
    Done := not IsValidChar(C);    
  until Done;

  // Test si la chaine en vaut la peine

  // Pas les chaines trop courtes ou numériques
  if MinLength and ((NumRead < MIN_LENGTH) or IsNumeric(Result)) then
    Result := '';
end;

(*procedure TXbeStringsExtractor.Add(StrPtrOffset, StrRawOffset: LongWord;
      Str, SectionName: string);
var
  EntryPtr: PBinaryEntry;

begin
  EntryPtr := New(PBinaryEntry);
  EntryPtr^.StrRawOffset := StrRawOffset;
  EntryPtr^.StrPtrOffset := StrPtrOffset;
  EntryPtr^.Str := Str;
  EntryPtr^.SectionName := SectionName;
  fExtractedStrings.Add(EntryPtr); // on stocke l'adresse
end;*)

(*procedure TXbeStringsExtractor.Clear;
var
  i: Integer;

begin
  for i := 0 to fExtractedStrings.Count - 1 do begin
    with PBinaryEntry(fExtractedStrings[i])^ do begin
      Str := ''; // détruire la string
      SectionName := '';
    end;
    Dispose(fExtractedStrings[i]);
  end;
end;*)

constructor TXbeStringsExtractor.Create;
begin
//  fExtractedStrings := TList.Create;
end;

destructor TXbeStringsExtractor.Destroy;
begin
//  Clear;
//  fExtractedStrings.Free;
  inherited;
end;

end.
