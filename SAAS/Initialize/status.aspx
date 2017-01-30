<%@ Import Namespace="System" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Web" %>
<%@ Import Namespace="System.Xml" %>
<%@ Import Namespace="System.Reflection" %>
<%@ Import Namespace="System.Diagnostics" %>
<%@ Page Language="c#" debug="true" %>
<html>
<head>
    <title>Microsoft Dynamics NAV 2017 Installation Status</title>
    <style type="text/css">
        body {
            font-family: "Segoe UI","Lucida Grande",Verdana,Arial,Helvetica,sans-serif;
            font-size: 16px;
            color: #c0c0c0;
            background: #000000;
            margin-left: 20px;
        }

    </style>
<script type="text/JavaScript">
function timeRefresh(timeoutPeriod) 
{
  setTimeout("location.reload(true);",timeoutPeriod);
}
</script>
</head>
<body onload="JavaScript:timeRefresh(10000);">
<%
   var lines = System.IO.File.ReadAllLines(@"c:\demo\status.txt");
   Array.Reverse(lines);
   foreach(var line in lines) {
%>
<%=line %><br>
<%
   }
%>
</body>
</html>
