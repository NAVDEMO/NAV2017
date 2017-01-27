<%@ Import Namespace="System" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Web" %>
<%@ Import Namespace="System.Xml" %>
<%@ Import Namespace="System.Reflection" %>
<%@ Page Language="c#" debug="true" %>
<script runat="server">

private XmlDocument customSettings = null;
private bool isSaaS = File.Exists(@"c:\inetpub\wwwroot\http\isSaaS.txt");

private void include(string Filename)
{
  Filename = Server.MapPath(".") + @"\" + Filename;
  if (File.Exists(Filename)) {
    Response.Write(File.ReadAllText(Filename));
  }
}

private string getHost()
{
  GetCustomSettings();
  var uri = new Uri(customSettings.SelectSingleNode("//appSettings/add[@key='PublicWebBaseUrl']").Attributes["value"].Value);
  return uri.Host;
}

private void GetCustomSettings()
{
  if (this.customSettings == null)
  {
    var dir = Directory.EnumerateDirectories(@"C:\Program Files\Microsoft Dynamics NAV").Last();
    customSettings = new XmlDocument();
    customSettings.Load(dir + @"\Service\CustomSettings.config");
  }
}

private string getCompanyName()
{
  GetCustomSettings();
  return customSettings.SelectSingleNode("//appSettings/add[@key='ServicesDefaultCompany']").Attributes["value"].Value;
}

private string getPowerBiUrl(bool unsecure)
{
  var company = getCompanyName();
  if (unsecure) {
    return "http://"+getHost()+"/UNSECURE/OData/Company('"+company+"')/";
  } else {
    return "https://"+getHost()+":7048/NAV/OData/Company('"+company+"')/";
  }
}

private string getSharePointUrl()
{
  var aspxFilename = @"c:\inetpub\wwwroot\NAV\WebClient\default.aspx";
  var aspx = File.ReadAllText(aspxFilename);
  var idx = aspx.IndexOf("\"Resources/Images/Office.png\"");
  if (idx > 0) {
    var length = aspx.Substring(idx).IndexOf("\", \"_self\"");
    var url = aspx.Substring(idx + 32, length);
    return url;
  }
  return "";
}

private string createQrImg(string link, string title, int width = 100, int height = 100)
{
  var encodedlink = System.Net.WebUtility.UrlEncode(link);
  return string.Format("<img src=\"https://chart.googleapis.com/chart?cht=qr&chs=100x100&chl={0}&chld=L|0\" title=\"{1}\" width=\"{2}\" height=\"{3}\" />", encodedlink, title, width, height);
}

private string createQrForLandingPage()
{
  return createQrImg(string.Format("http://{0}",getHost()), string.Format("Microsoft Dynamics NAV 2017 {0} <%=getPurpose() %> Environment Landing Page", getCountryVersion()));
}

private string getServerInstance()
{
  GetCustomSettings();
  return customSettings.SelectSingleNode("//appSettings/add[@key='ServerInstance']").Attributes["value"].Value;
}

private string getAzureSQL()
{
  GetCustomSettings();
  var DatabaseServer = customSettings.SelectSingleNode("//appSettings/add[@key='DatabaseServer']").Attributes["value"].Value;
  var DatabaseInstance = customSettings.SelectSingleNode("//appSettings/add[@key='DatabaseInstance']").Attributes["value"].Value;
  var DatabaseName = customSettings.SelectSingleNode("//appSettings/add[@key='DatabaseName']").Attributes["value"].Value;
  var len = DatabaseServer.IndexOf(".database.windows.net", StringComparison.OrdinalIgnoreCase);
  if (len>=0)
    return "Azure SQL<br />"+DatabaseServer+"<br />"+DatabaseName;
  if (!string.IsNullOrEmpty(DatabaseInstance))
    DatabaseInstance = "/"+DatabaseInstance;
  return "SQL Server<br />"+DatabaseServer+DatabaseInstance+"<br />"+DatabaseName;
}

private bool isMultitenant()
{
  GetCustomSettings();
  return bool.Parse(customSettings.SelectSingleNode("//appSettings/add[@key='Multitenant']").Attributes["value"].Value.ToLowerInvariant());
}

private string[] getTenants()
{
  try
  {
    var tenants = File.ReadAllLines(Server.MapPath(".") + @"\tenants.txt");
    Array.Sort<string>(tenants);
    return tenants;
  } catch {
    return new string[0];
  }
}

private string getCountryVersion()
{
  return Array.Find(System.IO.File.ReadAllLines(@"C:\DEMO\profiles.ps1"), line => line.Replace(" ", "").StartsWith("$Language=", StringComparison.InvariantCultureIgnoreCase)).Replace(" ", "").Substring(11, 2);
}

private string getBuildNumber()
{
  var dir = Directory.EnumerateDirectories(@"C:\Program Files\Microsoft Dynamics NAV").Last();
  return System.Diagnostics.FileVersionInfo.GetVersionInfo(dir+@"\Service\Microsoft.Dynamics.Nav.Server.exe").ProductVersion;
}

private string getProduct()
{
  return isSaaS ? "365" : "NAV 2017";
}

private string getPurpose()
{
  return isSaaS ? "Private Test" : "Demonstration";
}
</script>

<html>
<head>
    <title>Microsoft Dynamics <%=getProduct() %> <%=getCountryVersion() %> <%=getPurpose() %> Environment</title>
    <style type="text/css">
        h1 {
            font-size: 2em;
            font-weight: 400;
            color: #000;
            margin: 0px;
        }

        h2 {
            font-size: 1.2em;
            margin-top: 2em;
        }

        .h2sub {
            font-weight: 100;
        }

        h3 {
            font-size: 1.2em;
            margin: 0px;
            line-height: 32pt;
        }

        h4 {
            font-size: 1em;
            margin: 0px;
            line-height: 24pt;
        }

        h6 {
            font-size: 10pt;
            position: relative;
            left: 10px;
            top: 120px;
            margin: 0px;
        }

        h5 {
            font-size: 10pt;
        }

        body {
            font-family: "Segoe UI","Lucida Grande",Verdana,Arial,Helvetica,sans-serif;
            font-size: 12px;
            color: #5f5f5f;
            margin-left: 20px;
        }

        table {
            table-layout: fixed;
            width: 100%;
        }

        td {
            vertical-align: top;
        }

        a {
            text-decoration: none;
            text-underline:none
        }
        #tenants {
            border-collapse:collapse;
        }

        #tenants td {
            text-align: center;
            border: 1px solid #808080;
            vertical-align: middle;
            margin: 2px 2px 2px 2px;
        }

	#tenants tr.alt td {
            background-color: #e0e0e0;
        }

	#tenants tr.head td {
            background-color: #c0c0c0;
        }

        #tenants td.tenant {
            text-align: left;
        }
    </style>
<script language="javascript"> 
function show(selected) {
  document.getElementById("texttd").style.backgroundColor = "#cccccc"; 
  for(i=1; i<=5; i++) {
    var textele = document.getElementById("text"+i);
    var linkele = document.getElementById("link"+i);
    var tdele = document.getElementById("td"+i);
    if (i == selected) {
      textele.style.display = "block";
      tdele.style.backgroundColor = "#cccccc";
    } else {
      textele.style.display = "none";
      tdele.style.backgroundColor = "#ffffff";
    }
  }
} 

function showPowerBiUrl(unsecure) {
  if (unsecure == 1) {
    prompt("This is your OData Feed Url, press Ctrl+C to copy it to the clipboard", "<%=getPowerBiUrl(true) %>");
  } else {
    prompt("This is your OData Feed Url, press Ctrl+C to copy it to the clipboard", "<%=getPowerBiUrl(false) %>");
  }
}
</script>
</head>
<body>
  <table>
    <colgroup>
       <col span="1" style="width: 14%;">
       <col span="1" style="width: 70%;">
       <col span="1" style="width:  1%;">
       <col span="1" style="width: 15%;">
    </colgroup>
    <tr><td colspan="2">
    <table>
    <tr>
    <td rowspan="2" width="110"><% =createQrForLandingPage() %></td>
    <td style="vertical-align:bottom">&nbsp;<img src="Microsoft.png" width="108" height="23"></td>
    </tr><tr>
    <td style="vertical-align:top"><h1>Dynamics <%=getProduct() %> <%=getCountryVersion() %> <%=getPurpose() %> Environment</h1><%=getBuildNumber() %></td>
    </tr>
    </table>
    </td>
    <td></td>
    <td style="vertical-align:middle; color:#c0c0c0; white-space: nowrap"><p><%=getAzureSQL() %></p></td>
    </tr>
    <tr><td colspan="4"><img src="line.png" width="100%" height="14"></td></tr>
<%
  if (File.Exists(Server.MapPath(".") + @"\Certificate.cer")) {
%>
    <tr><td colspan="4"><h3>Download Self Signed Certificate</h3></td></tr>
    <tr>
      <td colspan="2">The <%=getPurpose() %> Environment is secured with a self-signed certificate. In order to connect to the environment, you must trust this certificate. Select operating system and browser to view the process for downloading and trusting the certificate:</td>
      <td></td>
      <td rowspan="2" style="white-space: nowrap"><a href="http://<% =getHost() %>/Certificate.cer" target="_blank">Download Certificate</a></td>
    </tr>
    <tr>
      <td colspan="2">
<table border="0" cellspacing="0" cellpadding="5"><tr>
<td style="width: 225px; white-space: nowrap" id="td1" style="background-color: #ffffff"><a id="link1" href="javascript:show(1);">Windows&nbsp;(Edge/IE/Chrome)</a></td>
<td style="width: 225px; white-space: nowrap" id="td2" style="background-color: #ffffff"><a id="link2" href="javascript:show(2);">Windows&nbsp;(Firefox)</a></td>
<td style="width: 225px; white-space: nowrap" id="td3" style="background-color: #ffffff"><a id="link3" href="javascript:show(3);">Windows&nbsp;Phone</a></td>
<td style="width: 225px; white-space: nowrap" id="td4" style="background-color: #ffffff"><a id="link4" href="javascript:show(4);">iOS&nbsp;(Safari)</a></td>
<td style="width: 225px; white-space: nowrap" id="td5" style="background-color: #ffffff"><a id="link5" href="javascript:show(5);">Android</a></td>
</tr>
<tr>
  <td colspan="5" id="texttd" style="background-color: #ffffff">
<div id="text1" style="display: none"><p>Download and open the certificate file. Click <i>Install Certificate</i>, choose <i>Local Machine</i>, and then place the certificate in the <i>Trusted Root Certification Authorities</i> category.</p></div>
<div id="text2" style="display: none"><p>Open Options, Advanced, View Certificates, Servers and then choose <i>Add Exception</i>. Enter <i>https://<% =getHost() %>/NAV</i>, choose <i>Get Certificate</i>, and then choose <i>Confirm Security Exception</i>.</p></div>
<div id="text3" style="display: none"><p>Choose the <i>download certificate</i> link. Install the certificate by following the certificate installation process.</p></div>
<div id="text4" style="display: none"><p>Choose the <i>download certificate</i> link. Install the certificate by following the certificate installation process.</p></div>
<div id="text5" style="display: none"><p>Choose the <i>download certificate</i> link. Launch the downloaded certificate, and then choose OK to install the certificate.</p></div>
  </td>
</tr>
</table>
      </td>
      <td colspan="2"></td>
    </tr>
<%
  }
  var rdps = System.IO.Directory.GetFiles(Server.MapPath("."), "*.rdp");
  if (rdps.Length > 0) {
%>
    <tr><td colspan="4"><h3>Remote Desktop Access</h3></td></tr>
<%
    for(int i=0; i<rdps.Length; i++) {
%>
      <tr>
        <td colspan="2">
<%
      if (i == 0) {
        if (rdps.Length > 1) {
%>
The <%=getPurpose() %> Environment contains multiple servers. You can connect to the individual servers by following these links.
<%
        } else {
%>
You can connect to the server in the <%=getPurpose() %> Environment by following this link.
<%
        }
      }
%>
        </td>
        <td></td>
        <td style="white-space: nowrap"><a href="http://<% =getHost() %>/<% =System.IO.Path.GetFileName(rdps[i]) %>"><% =System.IO.Path.GetFileNameWithoutExtension(rdps[i]) %></a></td>
      </tr>
<%
    }
  }
  if (System.IO.File.Exists(@"c:\demo\status.txt")) {
    var installing = System.IO.File.Exists(@"c:\demo\initialize.txt");
    if (installing) {
%>
      <tr><td colspan="4"><h3>Installation still running</h3></td></tr>
<%
    } else {
%>
      <tr><td colspan="4"><h3>Installation complete</h3></td></tr>
<%
    }
%>
      <tr>
        <td colspan="2">
You can view the installation status by following this link.
        </td>
        <td></td>
        <td style="white-space: nowrap"><a href="http://<% =getHost() %>/status.aspx" target="_blank">View Installation Status</a></td>
      </tr>
<%
  }
  if (!isMultitenant())
  {
  if (Directory.Exists(@"c:\inetpub\wwwroot\AAD")) {
%>
    <tr><td colspan="4"><h3>Access the <%=getPurpose() %> Environment using Microsoft Azure Active Directory or Office 365 authentication</h3></td></tr>
    <tr>
      <td colspan="2">If you have installed the Microsoft Dynamics NAV Universal App on your phone, tablet or desktop computer and want to configure the app to connect to this Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment, choose this link.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="ms-dynamicsnav://<% =getHost() %>/AAD">Configure App</a></td>
    </tr>
    <tr>
      <td colspan="2">Choose this link to access the <%=getPurpose() %> Environment using the Microsoft Dynamics <%=getProduct() %> Web client.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="https://<% =getHost() %>/AAD" target="_blank">Access Web Client</a></td>
    </tr>
<%
    var sharePointUrl = getSharePointUrl();
    if (!string.IsNullOrEmpty(sharePointUrl)) {
%>
    <tr>
      <td colspan="2">Choose this link to access the <%=getPurpose() %> Environment from Microsoft Dynamics <%=getProduct() %> embedded in an Office 365 SharePoint site.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="<% =sharePointUrl %>" target="_blank">Access SharePoint Site</a></td>
    </tr>
<%
    }
    if (File.Exists(@"c:\inetpub\wwwroot\AAD\WebClient\map.aspx")) {
%>
    <tr>
      <td colspan="2">The Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment is integrated with Bing Maps. Choose this link to view a map showing all customers.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="https://<% =getHost() %>/AAD/WebClient/map.aspx" target="_blank">Show Customer Map</a></td>
    </tr>
<%
    }
    if (Directory.Exists(Server.MapPath(".") + @"\AAD")) {
%>
    <tr>
      <td colspan="2">The Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment supports running the Microsoft Dynamics NAV Windows client over the internet. Choose this link to install the Microsoft Dynamics NAV Windows client using ClickOnce.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="http://<% =getHost() %>/AAD" target="_blank">Install Windows Client</a></td>
    </tr>
<%
    }
  }
  if (Directory.Exists(@"c:\inetpub\wwwroot\NAV")) {
%>
    <tr><td colspan="4"><h3>Access the <%=getPurpose() %> Environment using UserName/Password Authentication</h3></td></tr>
    <tr>
      <td colspan="2">If you have installed the Microsoft Dynamics NAV Universal App on your phone, tablet or desktop computer and want to configure the app to connect to this Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment, choose this link.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="ms-dynamicsnav://<% =getHost() %>/NAV">Configure App</a></td>
    </tr>
    <tr>
      <td colspan="2">Choose this link to access the <%=getPurpose() %> Environment using the Microsoft Dynamics <%=getProduct() %> Web client.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="https://<% =getHost() %>/NAV" target="_blank">Access Web Client</a></td>
    </tr>
<%
    if (File.Exists(@"c:\inetpub\wwwroot\NAV\WebClient\map.aspx")) {
%>
    <tr>
      <td colspan="2">The Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment is integrated with Bing Maps. Choose this link to view a map showing all customers.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="https://<% =getHost() %>/NAV/WebClient/map.aspx" target="_blank">Show Customer Map</a></td>
    </tr>
<%
    }
    if (Directory.Exists(Server.MapPath(".") + @"\NAV")) {
%>
    <tr>
      <td colspan="2">The Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment supports running the Microsoft Dynamics NAV Windows client over the internet. Choose this link to install the Microsoft Dynamics NAV Windows client using ClickOnce.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="http://<% =getHost() %>/NAV" target="_blank">Install Windows Client</a></td>
    </tr>
<%
    }
  }
%>
    <tr><td colspan="4"><h3>Integrate the <%=getPurpose() %> Environment with <a href="https://powerbi.microsoft.com" target="_blank">Power BI</a></h3></td></tr>
    <tr>
<%
  var company = getCompanyName();
  if (company.Contains("/")) {
%>
      <td colspan="2">The Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment is using a company name which includes a forward slash (<%=company %>).<br>Forward slash in the company name is not supported by Power BI.</td>
      <td></td>  
      <td></td>
<%
  } else if (File.Exists(Server.MapPath(".") + @"\Certificate.cer")) {
    var vdir = Directory.EnumerateDirectories(@"C:\Program Files\Microsoft Dynamics NAV").Last();
    if (Directory.Exists(vdir + @"\Service\Instances\UNSECURE")) {
%>
      <td colspan="2">When using the Microsoft Dynamics NAV Content Pack for Power BI, you need to specify an <i>OData Feed URL</i>. Click the link to get the URL.<br>You need to specify <i>Basic</i> authentication and use your NAV admin username and password for authentication.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="javascript:showPowerBiUrl(1);">Get OData Feed Url</a></td>
    </tr><tr>
      <td colspan="2"><b>Note:</b>  You will be connecting to an unsecure sevices endpoint. Your credentials will be sent over the wire in clear text. Consider using the Web Services Key instead of your password, as this won't give access to the <%=getPurpose() %> Environment if compromised, only the demo data will be compromised.</td>
      <td></td>  
      <td></td>
<%
    } else {
%>
      <td colspan="2">The Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment is secured with a self signed certificate. Power BI does not trust self signed certificates. Please run the PowerBI demo installer to expose Web Services UNSECURE, which will allow Power BI to connect.</td>
      <td></td>  
      <td></td>
    </tr><tr>
      <td colspan="2"><b>Note:</b>  When connecting to unsecure sevices endpoints, your credentials will be sent over the wire in clear text. Consider using the Web Services Key instead of your password, as this won't give access to the <%=getPurpose() %> Environment if compromised, only the demo data will be compromised.</td>
      <td></td>  
      <td></td>
<%
    }
%>
<%
  } else {
%>
    <td colspan="2">When using the Microsoft Dynamics NAV Content Pack for Power BI, you need to specify an <i>OData Feed URL</i>. Click the link to get the URL.<br>You need to specify <i>Basic</i> authentication and use your NAV admin username and password for authentication.</td>
    <td></td>  
    <td style="white-space: nowrap"><a href="javascript:showPowerBiUrl(0);">Get OData Feed Url</a></td>
<%
  }
%>
    </tr>
    <tr><td colspan="4"><h3>Access the <%=getPurpose() %> Environment using Web Services</h3></td></tr>
    <tr>
      <td colspan="2">The Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment exposes functionality as SOAP web services. Choose this link to view the web services.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="https://<% =getHost() %>:7047/NAV/WS/Services" target="_blank">View SOAP Web Services</a></td>
    </tr>
    <tr>
      <td colspan="2">The Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment exposes data as restful OData web services. Choose this link to view the web services</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="https://<% =getHost() %>:7048/NAV/OData" target="_blank">View OData Web Services</a></td>
    </tr>
<%
    if (File.Exists(@"c:\inetpub\wwwroot\http\NAV.webtile")) {
%>
    <tr>
      <td colspan="2">Download and open NAV.webtile on the phone, that is connected to your Microsoft Band in order to get a web tile which is connected to this Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment on your wrist.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="http://<% =getHost() %>/NAV.webtile" target="_blank">Download NAV.webtile</a></td>
    </tr>
<%
    }
    var dir = Directory.EnumerateDirectories(@"C:\Program Files\Microsoft Dynamics NAV").Last();
    if (Directory.Exists(dir + @"\Service\Instances\UNSECURE")) {
%>
    <tr><td colspan="4"><h3>Access the <%=getPurpose() %> Environment using UNSECURE Web Services</h3></td></tr>
    <tr><td colspan="2"><p>Your <%=getPurpose() %> environment is secured with a self signed certificate. PowerBI and some other online services cannot connect to services secured by a self signed certificate.<br /><b>Note:</b> that when connecting to unsecure sevices endpoints, your credentials will be sent over the wire in clear text. Consider using the Web Services Key instead of your password, as this won't give access to the <%=getPurpose() %> Environment if compromised, only the demo data will be compromised.</p></td><td colspan="2"></td></tr>
    <tr>
      <td colspan="2">The Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment exposes functionality as UNSECURE SOAP web services. Choose this link to view the web services.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="http://<% =getHost() %>/UNSECURE/WS/Services" target="_blank">View UNSECURE SOAP Web Services</a></td>
    </tr>
    <tr>
      <td colspan="2">The Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment exposes data as restful UNSECURE OData web services. Choose this link to view the web services</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="http://<% =getHost() %>/UNSECURE/OData" target="_blank">View UNSECURE OData Web Services</a></td>
    </tr>
<%
    }
  } 
  else
  {
var hardCodeInput = File.ReadAllText(@"C:\DEMO\Multitenancy\HardcodeInput.ps1");
var noSharePoint = hardCodeInput.Contains("$CreateSharePointPortal = $False");
var includeWindowsClient = !isSaaS;
var aid = isSaaS ? "&aid=fin" : "";
%>
    <tr><td colspan="4"><h3>Multitenant <%=getPurpose() %> Environment</h3></td></tr>
    <tr>
      <td colspan="4">
      <p>The Microsoft Dynamics <%=getProduct() %> <%=getPurpose() %> Environment is multitenant. The Tenants section lists the tenants, and you can choose links to access each of them.</p>
      <p>If you have installed the Microsoft Dynamics NAV Universal App on your phone, tablet or desktop computer and want to configure the app to connect to a tenant in this <%=getPurpose() %> Environment, choose the <i>Configure app</i> link.</p>
      <p>You can access this <%=getPurpose() %> Environment using the Microsoft Dynamics <%=getProduct() %> Web client by choosing the <i>Web Client</i> link.</p>
<%
if (includeWindowsClient) {
%>
      <p>You can access the <%=getPurpose() %> Environment from the Microsoft Dynamics NAV Windows client over the internet. You can install the Microsoft Dynamics <%=getProduct() %> Windows client and connect to a specific tenant using ClickOnce by choosing the <i>Windows Client</i> link.</p>
<%
}
%>
      <p>The <%=getPurpose() %> Environment exposes functionality as SOAP web services and restful OData web services. You can view the services by choosing the relevant link. <b>Note:</b> You must specify the tenant in the username (<i>&lt;tenant&gt;\&lt;username&gt;</i>).
      </td>
    </tr>
    <tr>
      <td colspan="4">
        <table id="tenants">
          <tr class="head">
            <td class="tenant"><b>Tenants</b></td>
<%
if (Directory.Exists(@"c:\inetpub\wwwroot\AAD")) {
%>
            <td colspan="<% =(File.Exists(@"c:\inetpub\wwwroot\AAD\WebClient\map.aspx")?3:2)+(noSharePoint?0:1) %>" align="center"><b>AAD or O365 Authentication</b></td>
<%
}
%>
            <td colspan="<% =(File.Exists(@"c:\inetpub\wwwroot\AAD\WebClient\map.aspx")?3:2)+(includeWindowsClient?1:0) %>" align="center"><b>Username/Password Authentication</b></td>
            <td colspan="2" align="center"><b>Web Services</b></td>
          </tr>
<%
var alt = false;
foreach(var tenant in getTenants())
{
if (alt) {
%>
          <tr class="alt">
<%
} else {
%>
          <tr>
<%
}
alt = !alt;
%>
            <td class="tenant">
              <b><% =tenant %></b>
            </td>
<%
if (Directory.Exists(@"c:\inetpub\wwwroot\AAD")) {
%>
            <td>
              <a href="ms-dynamicsnav://<% =getHost() %>/AAD?tenant=<% =tenant %>" target="_blank">Configure app</a>
            </td>
            <td>
              <a href="https://<% =getHost() %>/AAD?tenant=<% =tenant %><% = aid %>" target="_blank">Web Client</a>
            </td>
<%
if (!noSharePoint) {
%>
            <td>
              <a href="<% =getSharePointUrl() %>/sites/<% =tenant %>" target="_blank">SharePoint Site</a>
            </td>
<%
} 
if (File.Exists(@"c:\inetpub\wwwroot\AAD\WebClient\map.aspx")) {
%>
            <td>
              <a href="https://<% =getHost() %>/AAD/WebClient/map.aspx?tenant=<% =tenant %>" target="_blank">Customer Map</a>
            </td>
<%
}
}
%>
            <td>
              <a href="ms-dynamicsnav://<% =getHost() %>/NAV?tenant=<% =tenant %>" target="_blank">Configure app</a>
            </td>
            <td>
              <a href="https://<% =getHost() %>/NAV?tenant=<% =tenant %><% = aid %>" target="_blank">Web Client</a>
            </td>
<%
if (includeWindowsClient) {
%>
            <td>
<%
if (Directory.Exists(Server.MapPath(".") + @"\" + tenant)) {
%>
              <a href="http://<% =getHost() %>/<% =tenant %>" target="_blank">Windows Client</a>
<%
}
%>
            </td>
<%
}
if (File.Exists(@"c:\inetpub\wwwroot\NAV\WebClient\map.aspx")) {
%>
            <td>
              <a href="https://<% =getHost() %>/NAV/WebClient/map.aspx?tenant=<% =tenant %>" target="_blank">Customer Map</a>
            </td>
<%
}
%>
            <td>
              <a href="https://<% =getHost() %>:7047/NAV/WS/Services?tenant=<% =tenant %>" target="_blank">Soap Web Services</a>
            </td>
            <td>
              <a href="https://<% =getHost() %>:7048/NAV/OData?tenant=<% =tenant %>" target="_blank">OData Web Services</a>
            </td>
          </tr>
<%
}
%>
        </table>
      </td>
    </tr>
<%
  }
%>
    <tr><td colspan="4"><h3>Access the <%=getPurpose() %> Environment Help Server</h3></td></tr>
    <tr>
      <td colspan="2">Choose this link to access the Microsoft Dynamics <%=getProduct() %> Help Server.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="http://<% =getHost() %>:49000/main.aspx?lang=en&content=madeira-get-started.html" target="_blank">View Help Content</a></td>
    </tr>
    <tr><td colspan="4"><h3>Download the Microsoft Dynamics NAV Universal App</h3></td></tr>
    <tr>
      <td colspan="4">
        <a href="http://go.microsoft.com/fwlink/?LinkId=509974" target="_blank"><img src="WindowsStore.png" title="Download from Windows Store" width="200" height="59"></a>&nbsp;&nbsp;&nbsp;
        <a href="http://go.microsoft.com/fwlink/?LinkId=509975" target="_blank"><img src="AppStore.png" title="Download on the App Store" width="200" height="59"></a>&nbsp;&nbsp;&nbsp;
        <a href="http://go.microsoft.com/fwlink/?LinkId=509976" target="_blank"><img src="GooglePlay.png" title="Get it on Google Play" width="200" height="59"></a>
      </td>
    </tr>
    <tr>
      <td colspan="4">
<i>Apple and the Apple logo are trademarks of Apple Inc., registered in the U.S. and other countries. App Store is a service mark of Apple Inc.<br>Google Play is a trademark of Google Inc.</i>
      </td>
    </tr>
    <tr><td colspan="4">&nbsp;</td></tr>

  </table>
</body>
</html>