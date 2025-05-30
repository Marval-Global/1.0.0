BuildRequest
<%@ WebHandler Language="C#" Class="ApiHandler" %>

using System;
using Serilog;
using System.IO;
using System.Net;
using System.Web;
using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using MarvalSoftware.UI.WebUI.ServiceDesk.RFP.Plugins;

/// <summary>
/// ApiHandler
/// </summary>
public class ApiHandler : PluginHandler
{
    //properties
    private string UserAPIKey
    {
        get
        {
            return GlobalSettings["@@UserAPIKey"];
        }
    }



    private string BaseUrl
    {
        get
        {
            return HttpContext.Current.Request.Url.Scheme + "://api.statuspage.io/v1/";
        }
    }

    public class fullResponse
    {
        public int responseCode { get; set; }//res code
        public string responseDes { get; set; } //res desc
        public string responseBody { get; set; } //res body
    }

    /// <summary>
    /// Handle Request
    /// </summary>
    public override void HandleRequest(HttpContext context)
    {
        var action = context.Request.QueryString["action"];
        RouteRequest(action, context);
    }

    public override bool IsReusable
    {
        get { return false; }
    }

    /// <summary>
    /// Get request body value.
    /// </summary>
    /// <returns>Body value</returns>
    private string GetPostRequestData()
    {
        var streamReader = new StreamReader(HttpContext.Current.Request.InputStream);
        streamReader.BaseStream.Seek(0, SeekOrigin.Begin);
        return streamReader.ReadToEnd();
    }

    /// <summary>
    /// Check and return missing plugin settings
    /// </summary>
    /// <returns>Json Object containing any settings that failed the check</returns>
    private JObject PreRequisiteCheck()
    {
        var preReqs = new JObject();
        if (string.IsNullOrWhiteSpace(this.UserAPIKey))
        {
            preReqs.Add("userAPIKey", false);
        }

        return preReqs;
    }

    /// <summary>
    /// Route Request via Action
    /// </summary>
    private void RouteRequest(string action, HttpContext context)
    {
        HttpWebRequest httpWebRequest;
        switch (action)
        {
            case "PreRequisiteCheck":
                context.Response.Write(PreRequisiteCheck());
                break;
            case "GetAllPages":
                httpWebRequest = this.BuildRequest(this.BaseUrl + "pages");
                context.Response.Write(this.ProcessRequest(httpWebRequest));
                break;
            case "GetAllPageIncidents":
                httpWebRequest = this.BuildRequest(this.BaseUrl + string.Format("pages/{0}/incidents", context.Request.QueryString["pageId"]));
                context.Response.Write(this.ProcessRequest(httpWebRequest));
                break;
            case "GetAllIncidentUpdates":
                httpWebRequest = this.BuildRequest(this.BaseUrl + string.Format("pages/{0}/incidents/{1}", context.Request.QueryString["pageId"], context.Request.QueryString["incidentNumber"]));
                context.Response.Write(this.ProcessRequest(httpWebRequest));
                break;
            case "UpdateStatuspageIncident":
                Log.Information("Updating status incident page with " +this.GetPostRequestData());
                Log.Information("page id " + context.Request.QueryString["pageId"]);
                Log.Information("incident num " + context.Request.QueryString["incidentNumber"]);
                httpWebRequest = this.BuildRequest(this.BaseUrl + string.Format("pages/{0}/incidents/{1}", context.Request.QueryString["pageId"], context.Request.QueryString["incidentNumber"]), this.GetPostRequestData(), "PUT");
                context.Response.Write(this.ProcessRequest(httpWebRequest));
                break;
        }
    }

    /// <summary>
    /// Builds a HttpWebRequest
    /// </summary>
    /// <param name="uri">The uri for request</param>
    /// <param name="body">The body for the request</param>
    /// <param name="method">The verb for the request</param>
    /// <returns>The HttpWebRequest ready to be processed</returns>
    private HttpWebRequest BuildRequest(string uri = null, string body = null, string method = "GET")
    {
        //https://stackoverflow.com/a/2904963
        ServicePointManager.Expect100Continue = true;
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls12 | SecurityProtocolType.Ssl3;
        var request = WebRequest.Create(new UriBuilder(uri).Uri) as HttpWebRequest;
        request.Method = method.ToUpperInvariant();
        request.ContentType = "application/json";

        if (body != null)
        {
            using (var writer = new StreamWriter(request.GetRequestStream()))
            {
                writer.Write(body);
            }
        }

        return request;
    }

    /// <summary>
    /// Proccess a HttpWebRequest
    /// </summary>
    /// <param name="request">The HttpWebRequest</param>
    /// <param name="credentials">The Credentails to use for the API</param>
    /// <returns>Process Response</returns>
    private string ProcessRequest(HttpWebRequest request)
    {
        fullResponse myRes = new fullResponse();
        try
        {
            request.Headers.Add("Authorization", "Bearer " + this.UserAPIKey);
            HttpWebResponse response = request.GetResponse() as HttpWebResponse;
            var res = "";
            using (StreamReader reader = new StreamReader(response.GetResponseStream()))
            {
                return reader.ReadToEnd();
            }

            //return myRes;

        }
        catch (WebException webEx)
        {
            var result = "";
            var errStatus = ((HttpWebResponse)webEx.Response).StatusCode;
            var errResp = webEx.Response;

            myRes.responseCode = Int32.Parse(errStatus.ToString());
            myRes.responseDes = ((HttpWebResponse)errResp).StatusDescription;
            var res = "";
            using (StreamReader reader = new StreamReader(errResp.GetResponseStream()))
            {
                res= reader.ReadToEnd();
            }
            //myRes.responseBody = res;
            HttpContext.Current.Response.StatusCode = (int)errStatus;
            HttpContext.Current.Response.ContentType = "application/json";
            HttpContext.Current.Response.Write(res);
            HttpContext.Current.Response.End();

            //return myRes.responseCode.ToString() + res;
            return null;

            /*Log.Information("Have error response, response is " + errStatus);
            using (var stream = errResp.GetResponseStream())
            {
                using (var reader = new StreamReader(stream))
                {
                    result = reader.ReadToEnd();
                    Log.Information("Result from stream error " + result);
                }
            }*/
            //return myRes;
        }
    }
}