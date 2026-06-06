#Requires AutoHotkey v2.0

; =============================================================================
; WinOCR.ahk  —  Tesseract OCR version
; AHK v2 library for OCR via Tesseract 5 (LSTM engine)
;
; Requires: Tesseract portable (run setup.bat first)
; Supports: Win10 LTSC, Win10, Win11
;
; Usage:
;   #Include WinOCR.ahk
;   CoordMode "Pixel", "Screen"
;   result := WinOCR(100, 200, 300, 50)
;   if (ErrorLevel)
;       MsgBox "OCR failed: " ErrorLevel
;   else
;       MsgBox result
; =============================================================================

; =============================================================================
; Configurable (edit in source)
; =============================================================================

; Default scale factor (higher = better accuracy for small text)
; 1.0 = no scaling, 2.0 = 2x (recommended), 3.0 = 3x
global g_OCR_DefaultScale := 1.0

; Path to tesseract.exe (relative to script dir, or absolute)
; If empty or not found, auto-search common install locations
global g_OCR_Tesseract := ""

; Default OCR language(s). Use "+" to combine, e.g. "chi_sim+eng"
; Available after setup: chi_sim (Chinese), eng (English)
global g_OCR_Language := "chi_sim"

; Tesseract PSM (Page Segmentation Mode):
;   3 = Auto (default, good for general text)
;   6 = Uniform block of text (best for screen regions)
;   7 = Single text line
;   8 = Single word
global g_OCR_PSM := 6

; Temp file directory
; Tesseract may fail with Unicode paths; use script dir by default
global g_OCR_TempDir := ""  ; "" = use script dir; or set to e.g. "C:\Temp"

; =============================================================================
; Internal: GDI+ management
; =============================================================================

global __g_GdipStarted := false
global __g_GdipToken   := 0

__Gdip_Startup() {
    global __g_GdipStarted, __g_GdipToken
    if (__g_GdipStarted)
        return
    si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("UInt", 1, si, 0)
    DllCall("gdiplus.dll\GdiplusStartup",
        "UPtr*", &__g_GdipToken,
        "UPtr",  si.Ptr,
        "UPtr",  0)
    __g_GdipStarted := true
}

; =============================================================================
; Internal: Screen capture & image processing
; =============================================================================

__CaptureScreen(x, y, w, h) {
    hdcScreen := DllCall("GetDC", "UPtr", 0, "UPtr")
    hdcMem    := DllCall("CreateCompatibleDC", "UPtr", hdcScreen, "UPtr")
    hbm       := DllCall("CreateCompatibleBitmap", "UPtr", hdcScreen, "Int", w, "Int", h, "UPtr")
    hbmOld    := DllCall("SelectObject", "UPtr", hdcMem, "UPtr", hbm)
    DllCall("BitBlt",
        "UPtr", hdcMem,          "Int", 0, "Int", 0, "Int", w, "Int", h,
        "UPtr", hdcScreen,       "Int", x, "Int", y,
        "UInt", 0x00CC0020)
    DllCall("gdiplus.dll\GdipCreateBitmapFromHBITMAP",
        "UPtr",  hbm,   "UPtr", 0, "UPtr*", &pBitmap := 0)
    DllCall("SelectObject", "UPtr", hdcMem, "UPtr", hbmOld)
    DllCall("DeleteObject", "UPtr", hbm)
    DllCall("DeleteDC",     "UPtr", hdcMem)
    DllCall("ReleaseDC",    "UPtr", 0, "UPtr", hdcScreen)
    return pBitmap
}

__ScaleBitmap(pSrc, newW, newH) {
    DllCall("gdiplus.dll\GdipCreateBitmapFromScan0",
        "Int",  newW, "Int", newH, "Int", 0, "Int", 0x26200A,
        "UPtr", 0,     "UPtr*", &pDst := 0)
    DllCall("gdiplus.dll\GdipGetImageGraphicsContext",
        "UPtr",  pDst, "UPtr*", &g := 0)
    DllCall("gdiplus.dll\GdipSetInterpolationMode", "UPtr", g, "Int", 5)  ; NearestNeighbor (sharper for OCR)
    DllCall("gdiplus.dll\GdipSetPixelOffsetMode",   "UPtr", g, "Int", 4)
    DllCall("gdiplus.dll\GdipDrawImageRectI",
        "UPtr", g,    "UPtr", pSrc,
        "Int",  0,    "Int",  0,   "Int", newW, "Int", newH)
    DllCall("gdiplus.dll\GdipDeleteGraphics", "UPtr", g)
    DllCall("gdiplus.dll\GdipDisposeImage",   "UPtr", pSrc)
    return pDst
}

__SaveBitmapToPNG(pBitmap, filePath) {
    pngClsid := Buffer(16)
    NumPut("UInt",   0x557CF406, pngClsid, 0)
    NumPut("UShort", 0x1A04,     pngClsid, 4)
    NumPut("UShort", 0x11D3,     pngClsid, 6)
    NumPut("UChar",  0x9A, pngClsid,  8)
    NumPut("UChar",  0x73, pngClsid,  9)
    NumPut("UChar",  0x00, pngClsid, 10)
    NumPut("UChar",  0x00, pngClsid, 11)
    NumPut("UChar",  0xF8, pngClsid, 12)
    NumPut("UChar",  0x1E, pngClsid, 13)
    NumPut("UChar",  0xF3, pngClsid, 14)
    NumPut("UChar",  0x2E, pngClsid, 15)
    r := DllCall("gdiplus.dll\GdipSaveImageToFile",
        "UPtr", pBitmap, "UPtr", StrPtr(filePath),
        "UPtr", pngClsid.Ptr, "UPtr", 0)
    return (r = 0)
}

__DisposeBitmap(pBitmap) {
    DllCall("gdiplus.dll\GdipDisposeImage", "UPtr", pBitmap)
}

; =============================================================================
; Internal: Get temp directory (avoids Unicode path issues)
; =============================================================================

__GetTempDir() {
    global g_OCR_TempDir
    if (g_OCR_TempDir != "")
        return g_OCR_TempDir
    SplitPath(A_ScriptFullPath, , &scriptDir)
    return scriptDir
}

__TesseractOcr(imagePath, language := "") {
    global g_OCR_Tesseract, g_OCR_PSM

    ; Find tesseract.exe
    tessPath := __FindTesseract()
    if (tessPath = "") {
        ErrorLevel := "Tesseract not found. Install from https://github.com/UB-Mannheim/tesseract/releases"
        return ""
    }

    ; Resolve language
    lang := (language != "") ? language : g_OCR_Language

    ; Tesseract writes to file (preserves UTF-8 encoding) then read back
    tmp := __GetTempDir()
    outBase := tmp "\_WinOCR_result"
    outFile := outBase ".txt"

    cmd := Format('"{}" "{}" "{}" -l {} --psm {}', tessPath, imagePath, outBase, lang, g_OCR_PSM)
    exitCode := RunWait(cmd, , "Hide")

    output := ""
    try output := FileRead(outFile, "UTF-8-RAW")
    try FileDelete(outFile)

    if (exitCode != 0) {
        ErrorLevel := "Tesseract exit code: " exitCode " | Output: " Trim(output)
        return ""
    }

    ; Clean up: remove trailing form feeds Tesseract sometimes adds
    result := Trim(RegExReplace(output, "\x0c", ""), " `t`r`n")
    return result
}

; =============================================================================
; Internal: Auto-find tesseract.exe
; =============================================================================

__FindTesseract() {
    global g_OCR_Tesseract

    ; 1. Explicit path
    if (g_OCR_Tesseract != "" && FileExist(g_OCR_Tesseract))
        return g_OCR_Tesseract

    ; 2. Script-relative
    SplitPath(A_ScriptFullPath, , &scriptDir)
    if (g_OCR_Tesseract != "" && FileExist(scriptDir "\" g_OCR_Tesseract))
        return scriptDir "\" g_OCR_Tesseract

    ; 3. Common install locations
    paths := [
        "C:\Program Files\Tesseract-OCR\tesseract.exe",
        "C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
        A_AppData "\Tesseract-OCR\tesseract.exe",
        scriptDir "\tesseract\tesseract.exe"
    ]
    for p in paths {
        if (FileExist(p))
            return p
    }

    ; 4. PATH search
    for dir in StrSplit(EnvGet("PATH"), ";") {
        p := dir "\tesseract.exe"
        if (FileExist(p))
            return p
    }

    return ""
}

; =============================================================================
; Public: WinOCR_CheckSetup

; =============================================================================
; Public: WinOCR_CheckSetup
;
; Check if Tesseract is ready. Returns "" if OK, error description if not.
; =============================================================================

WinOCR_CheckSetup() {
    tessPath := __FindTesseract()
    if (tessPath = "") {
        return "Tesseract not found.`n`n"
             . "Install from:`n"
             . "https://github.com/UB-Mannheim/tesseract/releases`n`n"
             . "Or set g_OCR_Tesseract to the full path of tesseract.exe"
    }

    testCmd := Format('"{}" /c "{}" --version 1>nul 2>nul', A_ComSpec, tessPath)
    exitCode := RunWait(testCmd, , "Hide")
    if (exitCode != 0)
        return "Tesseract found but cannot execute.`nPath: " tessPath

    return ""
}

; =============================================================================
; Public: WinOCR
;
; OCR a screen region using Tesseract 5 LSTM engine.
;
; Parameters:
;   x1, y1    - Top-left coordinates (CoordMode "Pixel", "Screen")
;   width     - Region width in pixels
;   height    - Region height in pixels
;   scale     - Optional scale factor (default: g_OCR_DefaultScale, 2.0)
;   language  - Optional Tesseract language code(s)
;               "" = use g_OCR_Language (default "chi_sim+eng")
;               "eng" = English only
;               "chi_sim" = Chinese Simplified only
;               "chi_sim+eng" = both
;
; Returns:
;   Success → OCR text (multi-line with `n)
;   Failure → "" + ErrorLevel set
;
; Example:
;   #Include WinOCR.ahk
;   CoordMode "Pixel", "Screen"
;   result := WinOCR(100, 200, 300, 50)
;   if (ErrorLevel)
;       MsgBox "Failed: " ErrorLevel
;   else
;       MsgBox result
; =============================================================================

WinOCR(x1, y1, width, height, scale := unset, language := "") {
    global g_OCR_DefaultScale

    ErrorLevel := 0

    ; Validate
    s := IsSet(scale) ? scale : g_OCR_DefaultScale
    if (width <= 0 || height <= 0) {
        ErrorLevel := Format("WinOCR: Invalid size (width={1}, height={2})", width, height)
        return ""
    }
    if (s < 1.0) {
        ErrorLevel := "WinOCR: Scale must be >= 1.0 (got " s ")"
        return ""
    }

    ; Init GDI+
    __Gdip_Startup()

    ; Capture screen
    pBitmap := __CaptureScreen(x1, y1, width, height)
    if (!pBitmap) {
        ErrorLevel := "WinOCR: Screen capture failed"
        return ""
    }

    ; Scale up
    if (s > 1.0) {
        newW := Integer(width  * s)
        newH := Integer(height * s)
        pBitmap := __ScaleBitmap(pBitmap, newW, newH)
    }

    ; Save to temp PNG
    tmpDir := __GetTempDir()
    tmpFile := tmpDir "\_WinOCR_capture.png"
    if (!__SaveBitmapToPNG(pBitmap, tmpFile)) {
        __DisposeBitmap(pBitmap)
        ErrorLevel := "WinOCR: Failed to save temp PNG"
        return ""
    }
    __DisposeBitmap(pBitmap)

    ; OCR via Tesseract
    result := __TesseractOcr(tmpFile, language)
    try FileDelete(tmpFile)

    return result
}
