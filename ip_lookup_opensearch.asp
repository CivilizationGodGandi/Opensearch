<%@ Language=VBScript CodePage=949 %>
<%
Response.CharSet = "euc-kr"
Response.CodePage = 949

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

Function jsonEscape(value)
    value = Replace(CStr(value), "\", "\\")
    value = Replace(value, Chr(34), "\" & Chr(34))
    value = Replace(value, vbCr, "\r")
    value = Replace(value, vbLf, "\n")
    value = Replace(value, vbTab, "\t")
    jsonEscape = value
End Function

Function encodePowerShell(value)
    Dim stream, xml, node
    Set stream = Server.CreateObject("ADODB.Stream")
    stream.Type = 2
    stream.Charset = "unicode"
    stream.Open
    stream.WriteText value
    stream.Position = 0
    stream.Type = 1
    stream.Position = 2
    Set xml = Server.CreateObject("MSXML2.DOMDocument.6.0")
    Set node = xml.createElement("base64")
    node.dataType = "bin.base64"
    node.nodeTypedValue = stream.Read
    encodePowerShell = Replace(Replace(node.text, vbCr, ""), vbLf, "")
    stream.Close
    Set node = Nothing
    Set xml = Nothing
    Set stream = Nothing
End Function

Dim ip, ipAddress, abuseScore, countryCode, usageType, isp, domain, totalReports, distinctUsers, lastReportedAt, isTor, fullLog, wafReason, wafAction, aiResponse, topKoreanRule
ip = Request.QueryString("ip")

If ip <> "" Then
    ' AbuseIPDB 조회
    Dim http, url, apiKey, result
    apiKey = "ABUSEIPDB_API_KEY"
    url = "https://api.abuseipdb.com/api/v2/check?ipAddress=" & Server.URLEncode(ip) & "&maxAgeInDays=90"

    Set http = Server.CreateObject("MSXML2.ServerXMLHTTP")
    http.Open "GET", url, False
    http.setRequestHeader "Key", apiKey
    http.setRequestHeader "Accept", "application/json"
    http.Send
    result = http.responseText
    Set http = Nothing



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

    Dim riskText, riskColor, riskShake
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
	
    ' ===== OpenSearch 건수 조회: 단일 ASP 내부 처리 =====
    Dim osBaseUrl, osUser, osPassword, fwCount, wafCount
    Dim osShell, osProcess, osResult, osStderr, osError, osExitCode
    Dim psExe, psScript, osInput, psEncoded

    osBaseUrl = "https://222.233.121.38:9200/wazuh-alerts-*"
    osUser = "admin"
    osPassword = "SecretPassword"
    fwCount = ""
    wafCount = ""

    psScript = "$ErrorActionPreference = 'Stop'" & vbLf
    psScript = psScript & "$cfg = [Console]::In.ReadToEnd() | ConvertFrom-Json" & vbLf
    psScript = psScript & "Add-Type -TypeDefinition 'using System; using System.Net; public class OsCountClient : WebClient { public static void Configure() { ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12; ServicePointManager.ServerCertificateValidationCallback = (s,c,ch,e) => true; } protected override WebRequest GetWebRequest(Uri address) { WebRequest r = base.GetWebRequest(address); r.Timeout = 15000; HttpWebRequest h = r as HttpWebRequest; if (h != null) h.ReadWriteTimeout = 15000; return r; } }'" & vbLf
    psScript = psScript & "[OsCountClient]::Configure()" & vbLf
    psScript = psScript & "$client = New-Object OsCountClient" & vbLf
    psScript = psScript & "$client.Proxy = $null" & vbLf
    psScript = psScript & "$client.Headers['Authorization'] = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cfg.user + ':' + $cfg.password))" & vbLf
    psScript = psScript & "$result = @{}" & vbLf
    psScript = psScript & "foreach ($name in @('fwCount','wafCount')) {" & vbLf
    psScript = psScript & "    try {" & vbLf
    psScript = psScript & "        $device = if ($name -eq 'fwCount') { 'data.type:""traffic""' } else { 'decoder.name:""Monitorapp-data""' }" & vbLf
    psScript = psScript & "        $query = 'data.srcip:""' + $cfg.ip + '"" AND ' + $device" & vbLf
    psScript = psScript & "        $url = $cfg.baseUrl + '/_count?filter_path=count,_shards.failed,error&q=' + [Uri]::EscapeDataString($query)" & vbLf
    psScript = psScript & "        $response = $client.DownloadString($url) | ConvertFrom-Json" & vbLf
    psScript = psScript & "        if ($response._shards.failed -ne 0) {" & vbLf
    psScript = psScript & "            $result[$name] = 'ERROR SHARD_FAILURE'" & vbLf
    psScript = psScript & "        } elseif (($null -eq $response.count) -or (($response.count -isnot [int]) -and ($response.count -isnot [long])) -or ($response.count -lt 0)) {" & vbLf
    psScript = psScript & "            $result[$name] = 'ERROR INVALID_COUNT'" & vbLf
    psScript = psScript & "        } else {" & vbLf
    psScript = psScript & "            $result[$name] = [string]$response.count" & vbLf
    psScript = psScript & "        }" & vbLf
    psScript = psScript & "    } catch {" & vbLf
    psScript = psScript & "        $errorObject = $_.Exception" & vbLf
    psScript = psScript & "        while ($errorObject -and ($errorObject -isnot [Net.WebException])) { $errorObject = $errorObject.InnerException }" & vbLf
    psScript = psScript & "        if ($errorObject -and $errorObject.Response) {" & vbLf
    psScript = psScript & "            $result[$name] = 'ERROR HTTP ' + [int]$errorObject.Response.StatusCode" & vbLf
    psScript = psScript & "        } else {" & vbLf
    psScript = psScript & "            $detail = [regex]::Replace($_.Exception.Message, '[^A-Za-z0-9 _.:/-]', '?')" & vbLf
    psScript = psScript & "            $result[$name] = 'ERROR CONNECT ' + $detail.Substring(0, [Math]::Min(180, $detail.Length))" & vbLf
    psScript = psScript & "        }" & vbLf
    psScript = psScript & "    }" & vbLf
    psScript = psScript & "}" & vbLf
    psScript = psScript & "$client.Dispose()" & vbLf
    psScript = psScript & "$result | ConvertTo-Json -Compress" & vbLf

    If ipAddress <> "" Then
        osInput = "{""baseUrl"":""" & jsonEscape(osBaseUrl) & """,""user"":""" & jsonEscape(osUser) & """,""password"":""" & jsonEscape(osPassword) & """,""ip"":""" & jsonEscape(ipAddress) & """}"
        On Error Resume Next
        Err.Clear
        psEncoded = encodePowerShell(psScript)
        Set osShell = Server.CreateObject("WScript.Shell")
        psExe = osShell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
        Set osProcess = osShell.Exec(Chr(34) & psExe & Chr(34) & " -NoLogo -NoProfile -NonInteractive -EncodedCommand " & psEncoded)

        If Err.Number = 0 Then
            osProcess.StdIn.Write osInput
            osProcess.StdIn.Close
            osResult = osProcess.StdOut.ReadAll
            osStderr = osProcess.StdErr.ReadAll
            osExitCode = osProcess.ExitCode
        End If

        osError = Err.Description
        If Err.Number <> 0 Then
            fwCount = "조회 실패: " & osError
            wafCount = fwCount
            Err.Clear
        ElseIf osExitCode <> 0 Then
            fwCount = "조회 실패: HTTPS 호출 오류 " & osExitCode & " " & Left(osStderr, 200)
            wafCount = fwCount
        Else
            fwCount = extractJsonValue(osResult, "fwCount")
            wafCount = extractJsonValue(osResult, "wafCount")
            If fwCount = "" Then fwCount = "조회 실패: 건수 응답 없음"
            If wafCount = "" Then wafCount = "조회 실패: 건수 응답 없음"
            If Left(fwCount, 5) = "ERROR" Then fwCount = "조회 실패: " & fwCount
            If Left(wafCount, 5) = "ERROR" Then wafCount = "조회 실패: " & wafCount
        End If

        Set osProcess = Nothing
        Set osShell = Nothing
        On Error GoTo 0
    End If

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

    <table class="result-table">
        <tr><td class="label">▶ IP 주소</td><td><%=ipAddress%></td></tr>
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
        <li>방화벽 탐지 횟수: <%=Server.HTMLEncode(fwCount)%><% If IsNumeric(fwCount) Then Response.Write "건" %></li>
        <li>웹방화벽 탐지 횟수: <%=Server.HTMLEncode(wafCount)%><% If IsNumeric(wafCount) Then Response.Write "건" %></li>
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

