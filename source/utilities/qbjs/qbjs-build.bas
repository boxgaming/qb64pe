$Console:Only
Const ERROR_NO_NODEJS = 1, ERROR_NO_NETWORK = 2, ERROR_COMPILE_WARNINGS = 3
Const ERROR_NO_SOURCE = 4, ERROR_MULTIPLE_SOURCE = 5, ERROR_INVALID_OPTION = 6, ERROR_INVALID_MODE = 7
Option _Explicit
Dim Shared As String PORT, MODE, WARNING_FILE, PROGRAM_DIR
Dim Shared As Integer COMPILE_ONLY, NO_PROJECT_FILES, CLEAN
MODE = "auto"
PORT = "8080"

Type Dependency
    As String src
    As String dest
End Type
ReDim Shared dependencies(0) As Dependency
Dim Shared As String releaseTag, qbjsParentDir, qbjsDir, lastUpdate, destDir
Dim Shared As String sourceFilepath, filename, sourceDir
Dim Shared As Integer compileWarnings
PROGRAM_DIR = _CWD$

ParseArguments
CheckNodeJS
ReadConfig
GetCurrentRelease

' Initialize build paths
qbjsParentDir = _CWD$ + "internal" + PathSeparator + "qbjs"
qbjsDir = qbjsParentDir + PathSeparator + "qbjs-" + Mid$(releaseTag, 2)
filename = GetFilename(sourceFilepath)
sourceDir = GetParentPath(sourceFilepath)
If sourceDir = PathSeparator Then sourceDir = _StartDir$
Print "Source Directory: " + sourceDir
If sourceDir = PROGRAM_DIR Then NO_PROJECT_FILES = -1

DownloadQBJS
InitDependencies
CompileSource

If COMPILE_ONLY Then
    If compileWarnings Then System ERROR_COMPILE_WARNINGS
    System
End If

CopyWebDependencies
ChDir sourceDir
Print "NO_PROJECT_FILES: " + Str$(NO_PROJECT_FILES)
If Not NO_PROJECT_FILES Then
    Print "Copying project files..."
    ChDir sourceDir
    CopyProjectFiles ""
End If
Print "Build complete."

Dim url As String
url = "http://localhost:" + PORT + "/index.html"
StartWebserver url
Print "Launching page..."
LaunchURL url$
If compileWarnings Then System ERROR_COMPILE_WARNINGS
System

Sub ParseArguments
    Dim As Integer i, scount
    Dim As String arg, larg
    For i = 1 To _CommandCount
        arg = _Trim$(Command$(i))
        If Mid$(arg, 1, 1) <> "-" Then
            sourceFilepath = arg
            scount = scount + 1
        Else
            larg = UCase$(arg)
            If larg = "-COMPILEONLY" Then
                COMPILE_ONLY = -1
            ElseIf larg = "-NOPROJECTFILES" Then
                NO_PROJECT_FILES = -1
            ElseIf larg = "-CLEAN" Then
                CLEAN = -1
            ElseIf Len(larg) > 7 _AndAlso Mid$(larg, 1, 5) = "-PORT" Then
                PORT = Mid$(larg, 7, Len(larg) - 6)
            ElseIf Len(larg) > 7 _AndAlso Mid$(larg, 1, 5) = "-MODE" Then
                MODE = LCase$(Mid$(larg, 7, Len(larg) - 6))
                If MODE <> "auto" _AndAlso MODE <> "play" Then
                    Print "Invalid mode option: " + arg
                    Print "Valid modes are auto or play"
                    PrintUsage
                    System ERROR_INVALID_MODE
                End If
            ElseIf Len(larg) > 11 _AndAlso Mid$(larg, 1, 9) = "-WARNINGS" Then
                WARNING_FILE = Mid$(arg, 11, Len(arg) - 10)
                Print "WARNING_FILE=[" + WARNING_FILE + "]"
            Else
                Print "Invalid option: " + arg
                PrintUsage
                System ERROR_INVALID_OPTION
            End If
        End If
    Next i
    If sourceFilepath = "" Then
        Print "No source file specified."
        PrintUsage
        System ERROR_NO_SOURCE
    End If
    If scount > 1 Then
        Print "More than one source file specified."
        PrintUsage
        System ERROR_MULTIPLE_SOURCE
    End If
End Sub

Sub PrintUsage
    Print
    Print "USAGE:"
    Print
    Print "qbjs-build source-filename.bas [-port:8080] [-mode:auto|play] [-compileOnly] [-noProjectFiles] [-clean]"
End Sub

Sub ReadConfig
    ' Read release version and last update information
    If _FileExists(_CWD$ + ".qbjs") Then
        Open _CWD$ + ".qbjs" For Input As #1
        Input #1, releaseTag, lastUpdate
        Close #1
    End If
End Sub

Sub GetCurrentRelease
    Dim As String text, searchStr
    Dim As Integer sidx, eidx
    ' We probably don't need to check for new QBJS versions more than once per day
    If lastUpdate <> Date$ Then
        ' Lookup current release
        Print "Checking current QBJS release version..."
        ' If the _OpenClient method supports setting the User-Agent header in the future,
        ' the following URL would be preferred to lookup this information:
        ' https://api.github.com/repos/boxgaming/qbjs/releases/latest
        If DownloadFile("https://github.com/boxgaming/qbjs/releases/latest", "_qbjs_releases.txt") = 200 Then
            Print
            text = _ReadFile$("_qbjs_releases.txt")
            Kill "_qbjs_releases.txt"
            searchStr = "/boxgaming/qbjs/releases/tag/"
            sidx = InStr(text, searchStr) + Len(searchStr)
            eidx = InStr(sidx, text$, Chr$(34))
            releaseTag = Mid$(text, sidx, eidx - sidx)
            ' Save the current release information
            Open _CWD$ + ".qbjs" For Output As #1
            Write #1, releaseTag, Date$
            Close #1
        ElseIf releaseTag = "" Then
            Print "Unable to access QBJS repository, check network access."
            System ERROR_NO_NETWORK
        End If
    End If
    Print "QBJS Web Build:   " + releaseTag
End Sub

Sub DownloadQBJS
    If Not _DirExists(qbjsDir) Then
        ' Install QBJS
        If Not _DirExists(qbjsParentDir) Then MkDir qbjsParentDir

        Print "Downloading QBJS " + releaseTag + "...";
        Print DownloadFile("https://codeload.github.com/boxgaming/qbjs/zip/refs/tags/" + releaseTag, qbjsParentDir + PathSeparator + releaseTag + ".zip")
        Print "Download complete."
        Print "Unzipping QBJS..."
        $If WINDOWS Then
            Shell "cmd.exe /c" + Q$("cd " + _CWD$ + "internal/qbjs/ && tar -xf " + releaseTag + ".zip")
        $Else
            Shell "cd " + _CWD$ + "internal/qbjs/; unzip " + releaseTag + ".zip"
        $End If
        Print "Unzip complete."
        Print "Deleting zip."
        Kill qbjsParentDir + PathSeparator + releaseTag + ".zip"

        'Print "Compiling webserver..."
        'Dim ofile As String
        'ofile = "qbjs-webserver"
        '$If WINDOWS Then
        '    ofile = ofile + ".exe"
        '$End If
        'Shell "." + PathSeparator + "qb64pe -x " + Q$(qbjsDir + PathSeparator + "tools" + PathSeparator + "webserver.bas") + _
        '      " -o " + Q$(qbjsDir + PathSeparator + "tools" + PathSeparator + ofile)
    End If
End Sub

Sub CompileSource
    Dim As String warnings, warningFile
    destDir = sourceDir + PathSeparator + "_web"

    If CLEAN _AndAlso _DirExists(destDir) Then
        $If WINDOWS Then
            Shell "cmd.exe /c " + Q$("rmdir /s /q " + destDir)
        $Else
            Shell "rm -rf " + Q$(destDir)
        $End If
    End If

    warningFile = "_qbjs_warnings.txt"
    If WARNING_FILE <> "" Then warningFile = PROGRAM_DIR + WARNING_FILE

    If Not _DirExists(destDir) Then MkDir destDir
    ChDir sourceDir

    If _FileExists(warningFile) Then Kill warningFile
    Print
    Print "Compiling source file: " + filename + "..."

    Shell "node " + qbjsDir + PathSeparator + "qbc.js " + Q$(sourceFilepath) + " " + Q$(destDir + PathSeparator + "program.js") + "> " + Q$(warningFile)
    warnings = ""
    If _FileExists(warningFile) Then warnings = _Trim$(_ReadFile$(warningFile))
    If WARNING_FILE = "" Then
        If _FileExists(warningFile) Then Kill warningFile
    End If
    If warnings = "" Then
        warnings = "Compiled successfully with no errors or warnings"
        If _FileExists(warningFile) Then Kill warningFile
    Else
        compileWarnings = -1
    End If
    Print "-----------------------------------------------------------------------------"
    Print warnings
    Print "-----------------------------------------------------------------------------"
    If InStr(warnings, "ERROR:") Then System ERROR_COMPILE_WARNINGS
End Sub

Sub CopyWebDependencies
    Dim i As Integer
    Dim parent As String

    Print "Copy web dependencies..."
    For i = 1 To UBound(dependencies)
        parent = GetParentPath(dependencies(i).dest)
        If parent <> PathSeparator Then If Not _DirExists(destDir + PathSeparator + parent) Then MkDir destDir + PathSeparator + parent
        $If WINDOWS Then
            Shell "@echo off && cmd.exe /c " + Q$("copy /Y " + qbjsDir + PathSeparator + dependencies(i).src + " " + destDir + PathSeparator + dependencies(i).dest) + " > NUL"
        $Else
            Shell "\cp -f " + qbjsDir + PathSeparator + dependencies(i).src + " " + destDir + PathSeparator + dependencies(i).dest
        $End If
    Next i
End Sub

Sub CopyProjectFiles (path As String)
    Dim i As Integer
    Dim As String file, ext

    ReDim dirs(0) As String
    If Not _DirExists(destDir + PathSeparator + path) Then MkDir destDir + PathSeparator + path
    file = _Files$("")
    Do
        file = _Files$
        'Print "path: " + path + " | file: " + file
        If _DirExists(file) Then
            If file <> ".." + PathSeparator _AndAlso file <> "." + PathSeparator _AndAlso file <> "_web" + PathSeparator Then
                i = UBound(dirs) + 1
                ReDim _Preserve dirs(i) As String
                dirs(i) = file
            End If
        ElseIf file <> "" Then
            ext = LCase$(GetFileExtension$(file))
            If ext <> "exe" _AndAlso ext <> "bas" Then
                $If WINDOWS Then
                    Shell "@echo off && cmd.exe /c " + Q$("copy /Y " + file + " " + destDir + PathSeparator + path + " > NUL")
                $Else
                    Shell "\cp -f " + file + " " + destDir + PathSeparator + path
                $End If
            End If
        End If
    Loop Until file = ""

    For i = 1 To UBound(dirs)
        Print "cd " + path + dirs(i)
        'ChDir path + dirs(i)
        ChDir dirs(i)
        CopyProjectFiles path + dirs(i)
        ChDir ".."
    Next i
End Sub

Sub StartWebserver (url As String)
    Dim webServerDir As String
    webServerDir = qbjsDir + PathSeparator + "tools" + PathSeparator
    If Not TestFile(url) Then
        'If Not TestFile("http://localhost:" + PORT + "/_croot/" + sourceDir) Then
        Print "Starting http server..."
        ChDir destDir
        Shell _DontWait "cmd.exe /c " + Q$("title QBJS Web Server && node " + webServerDir + "qbjs-webserver.js " + PORT)
        '$If WINDOWS Then
        '   Shell _DontWait "cmd.exe /c " + Q$("title QBJS Web Server && " + qbjsDir + PathSeparator + "tools" + PathSeparator + "qbjs-webserver " + PORT)
        '$Else
        '    Shell _DontWait qbjsDir + PathSeparator + "tools" + PathSeparator + "qbjs-webserver " + PORT + " > /dev/null"
        '$End If
        'Else
        '    Dim result As Integer
        '    result = TestFile("http://localhost:" + PORT + "/_croot/" + sourceDir)
    Else
        _WriteFile webServerDir + ".root-path-override", destDir
    End If
End Sub

Sub CheckNodeJS
    Dim nodeVersion As String
    Shell "node --version > __nodeout.txt 2>&1"
    nodeVersion = _Trim$(_ReadFile$("__nodeout.txt"))
    nodeVersion = Replace$(nodeVersion, Chr$(10), "")
    nodeVersion = Replace$(nodeVersion, Chr$(13), "")
    Kill "__nodeout.txt"
    If Mid$(nodeVersion, 1, 1) <> "v" Then
        nodeVersion = ""
        Print "node.js not detected."
        Print "Please ensure that node.js is installed and is in the system path."
        LaunchURL "https://nodejs.org/en/download"
        System ERROR_NO_NODEJS
    End If

    Print "NodeJS Version:   " + nodeVersion
End Sub

Function GetFileExtension$ (filename As String)
    Dim i As Integer
    i = _InStrRev(filename, ".")
    GetFileExtension = Mid$(filename, i + 1)
End Function

Function Q$ (text As String)
    Q$ = Chr$(34) + text + Chr$(34)
End Function

Function TestFile (url As String)
    Dim result As Integer
    Dim h As Long
    h = _OpenClient(url)
    If h Then
        If _StatusCode(h) = 200 Then result = -1
        Close #h
    End If
    TestFile = result
End Function

Function DownloadFile (url As String, filename As String)
    Dim h As Long, content As String, s As String
    Dim As Integer statusCode

    h = _OpenClient(url)

    If h Then
        Open filename For Binary As #1
        statusCode = _StatusCode(h)

        While Not EOF(h)
            _Limit 60
            Get #h, , s
            Put #1, , s
            Print ".";
        Wend

        Close #h
        Close #1
    End If

    DownloadFile = statusCode
End Function

Sub LaunchURL (url As String)
    $If WIN Then
        Shell _DontWait _Hide "start " + url
    $ElseIf MAC Then
        Shell _DontWait _Hide "open " + url
    $ElseIf LINUX Then
        Shell _DontWait _Hide "xdg-open " + url
    $End If
End Sub

Function GetFilename$ (filepath As String)
    Dim s As String, i As Integer
    s = filepath
    s = Replace(s, "\", "/")
    i = _InStrRev(s, "/")
    s = Mid$(s, i + 1)
    GetFilename = s
End Function

Function GetParentPath$ (filepath As String)
    Dim s As String, i As Integer
    s = filepath
    s = Replace(s, "\", "/")
    i = _InStrRev(s, "/")
    s = Mid$(s, 1, i - 1)
    s = Replace(s, "/", PathSeparator)
    If s = "" Then s = PathSeparator
    GetParentPath = s
End Function

Function PathSeparator$ ()
    $If WINDOWS Then
        PathSeparator = "\"
    $Else
        PathSeparator = "/"
    $End If
End Function

Function Replace$ (s As String, searchString As String, newString As String)
    Dim ns As String
    Dim i As Integer

    Dim slen As Integer
    slen = Len(searchString)

    For i = 1 To Len(s) '- slen + 1
        If Mid$(s, i, slen) = searchString Then
            ns = ns + newString
            i = i + slen - 1
        Else
            ns = ns + Mid$(s, i, 1)
        End If
    Next i

    Replace = ns
End Function

Sub AddDependency (src As String, dest As String)
    Dim i As Integer
    i = UBound(dependencies) + 1
    ReDim _Preserve dependencies(i) As Dependency
    $If WINDOWS Then
        src = Replace$(src, "/", "\")
        dest = Replace$(dest, "/", "\")
    $End If
    dependencies(i).src = src
    dependencies(i).dest = dest
End Sub

Sub InitDependencies
    Dim As String depfile, src, dest

    ReDim dependencies(0) As Dependency
    AddDependency "export/" + MODE + ".html", "index.html"

    depfile = qbjsDir + PathSeparator + "export" + PathSeparator + "dependencies.txt"
    If Not _FileExists(depfile) Then
        Print "Missing dependencies file:"
        Print depfile
        'System
    End If

    Open depfile For Input As #1
    Input #1, src, dest
    While Not EOF(1)
        AddDependency src, dest
        Input #1, src, dest
    Wend
    Close #1
End Sub
