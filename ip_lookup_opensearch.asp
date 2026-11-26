<%@ Language=VBScript CodePage=949 %>
<%
Response.CharSet = "euc-kr"
Response.CodePage = 949
Server.ScriptTimeout = 300

If Left(Request.ServerVariables("REMOTE_ADDR"),11) = "222.233.121" Or Left(Request.ServerVariables("REMOTE_ADDR"),8) = "10.21.22" Or Left(Request.ServerVariables("REMOTE_ADDR"),8) = "10.21.23" Then
Else
	Response.Write "접근불가 IP 입니다."
	Response.End
End If

    Function extractJsonValue(jsonStr, key)
        Dim regex, m
        Set regex = New RegExp
        regex.Pattern = """" & key & """\s*:\s*(?:\""([^\""]+)\""|([0-9]+)|true|false|null)"
        regex.IgnoreCase = True
        Set m = regex.Execute(jsonStr)
        If m.Count > 0 Then
            If m(0).SubMatches(0) <> "" Then
                extractJsonValue = m(0).SubMatches(0)
            Else
                extractJsonValue = m(0).SubMatches(1)
            End If
        Else
            extractJsonValue = ""
        End If
        Set regex = Nothing
    End Function

Function windowsArg(value)
    windowsArg = Chr(34) & Replace(CStr(value), Chr(34), "\" & Chr(34)) & Chr(34)
End Function

Function readTextFile(fso, path)
    Dim file
    Set file = fso.OpenTextFile(path, 1)
    readTextFile = ""
    If Not file.AtEndOfStream Then readTextFile = file.ReadAll
    file.Close
End Function

Function getOpenSearchCount(baseUrl, userName, password, sourceIP, deviceQuery)
    Dim shell, fso, root, workDir, createdDir, bodyPath, errorPath
    Dim curlPath, command, query, url, code, body, detail, countValue, checkIP, poolName
    getOpenSearchCount = "조회 실패"
    createdDir = False
    Set checkIP = New RegExp
    checkIP.Pattern = "^[0-9A-Fa-f:.]{2,45}$"
    If Not checkIP.Test(sourceIP) Then
        getOpenSearchCount = "조회 실패: 올바르지 않은 IP"
        Exit Function
    End If

    query = "data.srcip:" & Chr(34) & sourceIP & Chr(34) & " AND " & deviceQuery
    url = baseUrl & "/_search?size=0&track_total_hits=true&timeout=10s&allow_partial_search_results=true&q=" & Server.URLEncode(query) & "&filter_path=timed_out,hits.total,_shards.failed,error"

    On Error Resume Next
    Err.Clear
    Do
        Set shell = Server.CreateObject("WScript.Shell")
        If Err.Number <> 0 Then Exit Do
        Set fso = Server.CreateObject("Scripting.FileSystemObject")
        If Err.Number <> 0 Then Exit Do
        root = shell.ExpandEnvironmentStrings("%SystemRoot%")
        workDir = fso.BuildPath(root & "\Temp", "os_" & fso.GetTempName)
        If Err.Number <> 0 Then Exit Do
        code = shell.Run(windowsArg(root & "\System32\cmd.exe") & " /d /q /c mkdir " & windowsArg(workDir), 0, True)
        If Err.Number <> 0 Then Exit Do
        If code <> 0 Then Exit Do
        createdDir = True

        command = windowsArg(root & "\System32\icacls.exe") & " " & windowsArg(workDir)
        command = command & " /grant " & windowsArg("*S-1-5-17:(OI)(CI)M")
        poolName = Request.ServerVariables("APP_POOL_ID")
        If poolName <> "" Then command = command & " " & windowsArg("IIS AppPool\" & poolName & ":(OI)(CI)M")
        code = shell.Run(command, 0, True)
        If Err.Number <> 0 Then Exit Do
        If code <> 0 Then Exit Do

        bodyPath = fso.BuildPath(workDir, "body.tmp")
        errorPath = fso.BuildPath(workDir, "error.tmp")
        curlPath = root & "\System32\curl.exe"
        If Not fso.FileExists(curlPath) Then curlPath = root & "\Sysnative\curl.exe"
        If Err.Number <> 0 Then Exit Do
        command = windowsArg(curlPath) & " --disable --silent --show-error --fail --insecure --ssl-no-revoke"
        command = command & " --tlsv1.2 --tls-max 1.2 --globoff --proxy " & windowsArg("")
        command = command & " --connect-timeout 5 --max-time 120 --get"
        command = command & " --user " & windowsArg(userName & ":" & password)
        command = command & " --url " & windowsArg(url)
        command = command & " --output " & windowsArg(bodyPath) & " --stderr " & windowsArg(errorPath)
        code = shell.Run(command, 0, True)
        If Err.Number <> 0 Then Exit Do
        If code <> 0 Then
            detail = readTextFile(fso, errorPath)
            If Err.Number <> 0 Then Exit Do
            getOpenSearchCount = "조회 실패 CURL " & code & ": " & Left(Trim(detail), 500)
            Exit Do
        End If

        body = readTextFile(fso, bodyPath)
        If Err.Number <> 0 Then Exit Do
        countValue = extractJsonValue(body, "value")
        checkIP.Pattern = """timed_out""\s*:\s*true"
        If extractJsonValue(body, "failed") <> "0" And Not checkIP.Test(body) Then
            getOpenSearchCount = "조회 실패: ERROR SHARD_FAILURE"
        ElseIf countValue = "" Then
            getOpenSearchCount = "조회 실패: ERROR INVALID_COUNT"
        Else
            getOpenSearchCount = countValue
            If checkIP.Test(body) Or extractJsonValue(body, "relation") = "gte" Then
                getOpenSearchCount = countValue & "+"
            End If
        End If
    Loop While False

    If Err.Number <> 0 Then getOpenSearchCount = "조회 실패 [" & Hex(Err.Number) & "]: " & Err.Description
    Err.Clear
    If createdDir Then shell.Run windowsArg(root & "\System32\cmd.exe") & " /d /q /c rmdir /s /q " & windowsArg(workDir), 0, True
    Set fso = Nothing
    Set shell = Nothing
    Err.Clear
    On Error GoTo 0
End Function

Dim abuseError, abuseStatus, abuseRequestError
Dim ip, ipAddress, abuseScore, countryCode, usageType, isp, domain, totalReports, distinctUsers, lastReportedAt, isTor, fullLog, wafReason, wafAction, aiResponse, topKoreanRule
ip = Request.QueryString("ip")

If ip <> "" Then
    ' AbuseIPDB 조회
    Dim http, url, apiKey, result
    apiKey = "ABUSEIPDB_API_KEY"
    url = "https://api.abuseipdb.com/api/v2/check?ipAddress=" & Server.URLEncode(ip) & "&maxAgeInDays=90"

    abuseError = ""
    abuseStatus = 0
    result = ""
    On Error Resume Next
    Err.Clear
    Set http = Server.CreateObject("MSXML2.ServerXMLHTTP")
    http.setTimeouts 5000, 5000, 10000, 10000
    http.Open "GET", url, False
    http.setRequestHeader "Key", apiKey
    http.setRequestHeader "Accept", "application/json"
    http.Send
    If Err.Number = 0 Then
        abuseStatus = http.Status
        result = http.responseText
    End If
    abuseRequestError = Err.Description
    If Err.Number <> 0 Then
        abuseError = "AbuseIPDB 조회 실패: " & abuseRequestError
        Err.Clear
    ElseIf abuseStatus <> 200 Then
        abuseError = "AbuseIPDB 조회 실패 HTTP " & abuseStatus
    End If
    Set http = Nothing
    On Error GoTo 0

    ipAddress      = extractJsonValue(result, "ipAddress")
    abuseScore     = extractJsonValue(result, "abuseConfidenceScore")
    countryCode    = extractJsonValue(result, "countryCode")
    usageType      = extractJsonValue(result, "usageType")
    isp            = extractJsonValue(result, "isp")
    domain         = extractJsonValue(result, "domain")
    totalReports   = extractJsonValue(result, "totalReports")
    distinctUsers  = extractJsonValue(result, "numDistinctUsers")
    lastReportedAt = extractJsonValue(result, "lastReportedAt")
    isTor          = extractJsonValue(result, "isTor")

    If ipAddress = "" Then
        ipAddress = ip
        If abuseError = "" Then abuseError = "AbuseIPDB 조회 실패: IP 응답 없음"
    End If


    Dim riskText, riskColor, riskShake
    riskText = "조회 실패"
    riskColor = "gray"
    riskShake = ""
    If abuseScore <> "" Then
        If CLng(abuseScore) <= 30 Then
            riskText = "낮음"
            riskColor = "green"
            riskShake = ""
        ElseIf CLng(abuseScore) <= 60 Then
            riskText = "중간"
            riskColor = "orange"
            riskShake = ""
        Else
            riskText = "높음"
            riskColor = "red"
            riskShake = "animation: shake 0.3s infinite;"
        End If
    End If
	
    ' ===== OpenSearch 건수만 조회 =====
    Dim osBaseUrl, osUser, osPassword, fwCount, wafCount
    osBaseUrl = "https://222.233.121.38:9200/wazuh-archives-*"
    osUser = "admin"
    osPassword = "SecretPassword"

    fwCount = getOpenSearchCount(osBaseUrl, osUser, osPassword, ipAddress, "location:""210.116.108.137""")
    wafCount = getOpenSearchCount(osBaseUrl, osUser, osPassword, ipAddress, "location:""210.116.108.249""")

    ' ===== AI 호출 =====
    If wafReason <> "" Then
        Dim aiHttp, aiUrl, aiReqBody, aiKey, aiResult, aiRegex, aiMatch
        aiUrl = "https://openrouter.ai/api/v1/chat/completions"
        aiKey = "Bearer OPENROUTER_API_KEY"
        aiReqBody = "{""model"":""nvidia/nemotron-3-ultra-550b-a55b:free"",""messages"":["
        aiReqBody = aiReqBody & "{""role"":""user"",""content"":""" & Replace(topKoreanRule & " 패턴이 매칭 되었고 조치는 " & wafAction & " 이고 패턴 매칭 근거는 " & wafReason & " 이야 취약한 부분과 탐지 근거에 대해서 한국어로 짧게 요약해서 설명해줘", """", "\""") & """}"
        aiReqBody = aiReqBody & "],""temperature"":0.7}"

        Set aiHttp = Server.CreateObject("MSXML2.ServerXMLHTTP")
        aiHttp.Open "POST", aiUrl, False
        aiHttp.setRequestHeader "Authorization", aiKey
        aiHttp.setRequestHeader "Content-Type", "application/json"
        aiHttp.Send aiReqBody
        aiResult = aiHttp.responseText
        Set aiHttp = Nothing

        Set aiRegex = New RegExp
        aiRegex.Pattern = """content"":\s*""((?:[^""\\]|\\.)*)"""
        aiRegex.Global = False
        aiRegex.IgnoreCase = True

        Set aiMatch = aiRegex.Execute(aiResult)
        If aiMatch.Count > 0 Then
            aiResponse = aiMatch(0).SubMatches(0)
            aiResponse = Replace(aiResponse, "*", "")
            aiResponse = Replace(aiResponse, "\n", "<br>")
            aiResponse = Replace(aiResponse, "<br><br>", "<br>")
        End If
    End If
End If
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="euc-kr">
    <title>Multiple IP Lookup</title>
    <style>
        body { font-family: Malgun Gothic, sans-serif; margin-left: 40px; }
        @keyframes shake {
            0% { transform: translate(1px, 0); }
            50% { transform: translate(-1px, 0); }
            100% { transform: translate(1px, 0); }
        }
        .result-table { margin-top: 20px; border-collapse: collapse; }
        .result-table td { padding: 4px 12px; text-align: left; }
        .label { font-weight: bold; width: 160px; }
    </style>
</head>
<body>
    <div class="header_logo">
        <img src="/resources/logo_ybmfamily.svg" alt="YBM Family">
    </div>

    <% If ipAddress <> "" Then %>
    <div style="margin-top: 20px;">
        <img src="/resources/checkpage_icon_character.svg" width="60" style="display: block; margin-bottom: 5px;">
        <div style="font-size: 18px; font-weight: bold; color:<%=riskColor%>; <%=riskShake%>">
            위험도: <%=riskText%>
        </div>
    </div>

    <h2 style="margin-top: 30px;">wow 페이지 출발지 IP DB 내역 호출 및 AI 분석 내역</h2>

    <% If abuseError <> "" Then %>
    <div style="color:red;"><%=Server.HTMLEncode(abuseError)%></div>
    <% End If %>

    <table class="result-table">
        <tr><td class="label">▶ IP 주소</td><td><%=Server.HTMLEncode(ipAddress)%></td></tr>
        <tr><td class="label">▶ 위험도 점수</td><td style="color:<%=riskColor%>; <%=riskShake%>"><%=abuseScore%> / 100</td></tr>
        <tr><td class="label">▶ 국가 코드</td><td><%=countryCode%></td></tr>
        <tr><td class="label">▶ 사용 유형</td><td><%=usageType%></td></tr>
        <tr><td class="label">▶ ISP</td><td><%=isp%></td></tr>
        <tr><td class="label">▶ 도메인</td><td><%=domain%></td></tr>
        <tr><td class="label">▶ 전체 신고 수</td><td><%=totalReports%></td></tr>
        <tr><td class="label">▶ 신고한 사용자 수</td><td><%=distinctUsers%></td></tr>
        <tr><td class="label">▶ 마지막 신고일</td><td><%=lastReportedAt%></td></tr>
        <tr><td class="label">▶ TOR 여부</td><td><%=isTor%></td></tr>
    </table>

    <h3 style="margin-top:30px;">내부 보안 장비 탐지 이력</h3>
    <ul>
        <li>방화벽 탐지 횟수: <%=Server.HTMLEncode(fwCount)%><% If IsNumeric(fwCount) Or Right(fwCount, 1) = "+" Then Response.Write "건" %></li>
        <li>웹방화벽 탐지 횟수: <%=Server.HTMLEncode(wafCount)%><% If IsNumeric(wafCount) Or Right(wafCount, 1) = "+" Then Response.Write "건" %></li>
        <li>가장 많이 탐지된 룰명: <%'=topKoreanRule%></li>
    </ul>

    <% If aiResponse <> "" Then %>
        <h3 style="margin-top:30px;">AI 분석 결과</h3>
        <div style="border:1px solid #ccc; padding:10px; background-color:#f9f9f9;">
            <%=aiResponse%>
        </div>
    <% End If %>
    <% End If %>
</body>
</html>

