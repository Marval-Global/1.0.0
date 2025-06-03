<%@ WebHandler Language="C#" Class="ApiHandler" %>

using System;
using Serilog;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Text;
using System.Web;
using System.Linq;
using System.Web.Http;
using System.Threading.Tasks;
using System.Collections.Specialized;
using Newtonsoft.Json;
using Newtonsoft.Json.Converters;
using Newtonsoft.Json.Linq;
using MarvalSoftware.Data.ServiceDesk;
using MarvalSoftware.UI.WebUI.ServiceDesk.RFP.Plugins;
using MarvalSoftware.DataTransferObjects;
using MarvalSoftware.ServiceDesk.Facade;
using System.Text.RegularExpressions;

public class ApiHandler : PluginHandler
{
    public override bool IsReusable
    {
        get { return false; }
    }

    private string SlackAppOAuthToken
    {
        get
        {
            return this.GlobalSettings["@@SlackAppOAuthToken"];
        }
    }

    private string MSMApiKey
    {
        get
        {
            return this.GlobalSettings["@@MSMApiKey"];
        }
    }

    private string NoteType
    {
        get
        {
            return this.GlobalSettings["@@NoteType"];
        }
    }

    private string EnableMobileDeepLink
    {
        get
        {
            return this.GlobalSettings["@@EnableMobileLink"];
        }
    }

    private int RequestId { get; set; }

    private string Action { get; set; }

    private string BaseNoteUrl
    {
        get
        {
            return HttpContext.Current.Request.Url.Scheme + "://" + HttpContext.Current.Request.Url.Host + "/MSM/api/serviceDesk/operational/requests/{0}/notes";
        }
    }

    private string BaseUrl
    {
        get
        {
            return "https://slack.com/api/";
        }
    }

    private string ServiceDeskBaseUrl
    {
        get
        {
            if (this.EnableMobileDeepLink == "1")
            {
                return ApiHandler.CreateAppLink(this.RequestId, HttpContext.Current.Request.Url.Scheme + "://" + HttpContext.Current.Request.Url.Host + MarvalSoftware.UI.WebUI.ServiceDesk.WebHelper.ApplicationPath);
            }
            else
            {
                return HttpContext.Current.Request.Url.Scheme + "://" + HttpContext.Current.Request.Url.Host + MarvalSoftware.UI.WebUI.ServiceDesk.WebHelper.ApplicationPath + "/RFP/Forms/Request.aspx?id=" + this.RequestId;
            }
        }
    }

    private string SelfServiceBaseUrl
    {
        get
        {
            var baseForSelfService = MarvalSoftware.Servers.ServerManager.ConfigurationDetails.ConfigurationSettings.SurveysSelfSeriveBaseUrl;
            var selfServiceBaseUrl = !baseForSelfService.Contains("https") ? baseForSelfService.Replace("http", HttpContext.Current.Request.Url.Scheme) : baseForSelfService;
            return string.Format("{0}/ViewRequest.aspx?requestId={1}", selfServiceBaseUrl, this.RequestId);
        }
    }

    public override void HandleRequest(HttpContext context)
    {
        this.ProcessParameters(context);
        this.RouteRequest(context);
    }

    private void RouteRequest(HttpContext context)
    {
        switch (this.Action)
        {
            case "PreRequisiteCheck":
                context.Response.Write(this.PreRequisiteCheck());
                break;
            case "PublishToSlack":
                context.Response.Write(this.PublishToSlack(context));
                break;
            case "AssociateFromSlack":
                this.ProcessSlackAssociation(context);
                break;
        }
    }

    private void ProcessParameters(HttpContext context)
    {
        this.Action = context.Request.QueryString["action"];
        int requestId = 0;
        int.TryParse(context.Request.QueryString["requestId"], out requestId);
        this.RequestId = requestId;
    }

    private void ProcessSlackAssociation(HttpContext context)
    {
        var slackClient = new SlackClient(this.BaseUrl, this.SlackAppOAuthToken);
        new SlackWebhookHelper(slackClient, context.Request.Form, this.BaseNoteUrl, this.MSMApiKey, this.NoteType).VerifyRequest();
    }

    private string PublishToSlack(HttpContext context)
    {
        var slackClient = new SlackClient(this.BaseUrl, this.SlackAppOAuthToken);
        int requestId;
        int.TryParse(context.Request.QueryString["requestId"], out requestId);
        var request = this.ViewRequest(requestId, this.ServiceDeskBaseUrl, this.SelfServiceBaseUrl);
        if (requestId == 0)
        {
            using (Stream receiveStream = context.Request.InputStream)
            {
                using (StreamReader readStream = new StreamReader(receiveStream, Encoding.UTF8))
                {
                    return readStream.ReadToEnd();
                }
            }
        }
        else
        {
            dynamic response = slackClient.GetAllChannels();
            if ((bool)response.ok.Value)
            {
                var channelId = slackClient.DoesChannelExist(request.Text, response);
                if (!string.IsNullOrEmpty(channelId))
                {
                    return slackClient.PostMessage(channelId, request);
                }
                else
                {
                    var newChannelId = slackClient.CreateChannel(BaseUrl + "conversations.create", request.Text, "POST");
                    return slackClient.PostMessage(newChannelId, request);
                }
            }
            else
            {
                return JsonConvert.SerializeObject(response);
            }
        }
    }

    private JObject PreRequisiteCheck()
    {
        var preReqs = new JObject();
        if (string.IsNullOrWhiteSpace(this.SlackAppOAuthToken))
        {
            preReqs.Add("slackAppOAuthToken", false);
        }

        return preReqs;
    }

    public static string CreateAppLink(int requestId, string serverUrl)
    {
        var apiUriBuilder = new UriBuilder(serverUrl);
        apiUriBuilder.Path += @"/api/serviceDesk/operational/requests/" + requestId;
        var malUriBuilder = new UriBuilder("https://mal.marval.co.uk");
        var query = HttpUtility.ParseQueryString(malUriBuilder.Query);
        query["url"] = apiUriBuilder.Uri.AbsoluteUri;
        malUriBuilder.Query = query.ToString();
        return malUriBuilder.Uri.AbsoluteUri;
    }

    public SlackClient.Payload ViewRequest(int requestId, string serviceDeskUrl, string selfServiceUrl)
    {
        var request = new RequestBroker().Find(requestId);
        return new SlackClient.Payload
        {
            ResponseType = "in_channel",
            Text = request.FullRequestNumber,
            Attachments = new SlackClient.Payload.Attachment[] {
                new SlackClient.Payload.Attachment()
                {
                    Title = "Description",
                    Text = request.Description,
                    Color = "#000000"
                },
                new SlackClient.Payload.Attachment()
                {
                    Title = "Assignee",
                    Text =  request.Assignee.Assignee.NameString,
                    Color = "#FED904"
                },
                new SlackClient.Payload.Attachment()
                {
                    Title = "Status Information",
                    Color = "#F07204",
                    fields = new SlackClient.Payload.Attachment.field[]
                    {
                        new SlackClient.Payload.Attachment.field()
                        {
                            Title = "Status",
                            Value = request.CurrentStatus.StatusName,
                            Short = false
                        },
                        new SlackClient.Payload.Attachment.field()
                        {
                            Title = "Occurred",
                            Value = request.DateOccurred.ToShortDateString() + " - " + request.DateOccurred.ToLocalTime().ToString(@"HH:mm"),
                            Short = false
                        },
                        new SlackClient.Payload.Attachment.field()
                        {
                            Title = "Risk",
                            Value = request.Risk.Value.ToString(),
                            Short = false
                        },
                    }
                },
                new SlackClient.Payload.Attachment()
                {
                    Fallback = "Self Service or Service Desk?",
                    Color = "#85BB27",
                    AttachmentType = "defualt",
                    Actions = new SlackClient.Payload.Action[]
                    {
                        new SlackClient.Payload.Action()
                        {
                            Name = "ServiceDesk",
                            Text = "View in Service Desk",
                            Type = "button",
                            Value = "View in Service Desk",
                            Url = ServiceDeskBaseUrl
                        },
                        new SlackClient.Payload.Action()
                        {
                            Name = "SelfService",
                            Text = "View in Self Service",
                            Type = "button",
                            Value = "View in Self Service",
                            Url = SelfServiceBaseUrl
                        }
                    }
                },
            }
        };
    }

    public class SlackWebhookHelper : ApiController
    {
        private SlackClient slackClient;
        private NameValueCollection form;
        private string baseNoteUrl;
        private string apiKey;
        private string noteType;
        private RequestTypeInfo[] RequestTypes { get; set; }

        public SlackWebhookHelper(SlackClient slackClient, NameValueCollection form, string baseNoteUrl, string apiKey, string noteType)
        {
            this.slackClient = slackClient;
            this.form = form;
            this.apiKey = apiKey;
            this.baseNoteUrl = baseNoteUrl;
            this.noteType = noteType;
        }

        public IHttpActionResult VerifyRequest()
        {
            IHttpActionResult httpActionResult = null;
            var tasks = new[]
            {
                Task.Run(() => this.AssociateFromSlack())
            };

            return httpActionResult = this.Ok("ok");
        }

        public static int ExtractRequestNumber(RequestTypeInfo[] requestTypes, List<KeyValuePair<string, string>> tags, string subject)
        {
            int requestNumber = 0;
            var searchRegExPattern = new Regex(string.Format(@"\b({0})\s*-\s*\d+\b", string.Join("|", requestTypes.Select(x => x.Acronym).ToList())), RegexOptions.IgnoreCase);
            var valueRegExPattern = new Regex(@"\d+");
            var foundMatches = searchRegExPattern.Matches(subject);

            if ((from Match matched in foundMatches select valueRegExPattern.Match(matched.Value)).Any(foundRequestNumber => foundRequestNumber.Success && Int32.TryParse(foundRequestNumber.Value, out requestNumber)))
            {
                return requestNumber;
            }

            return requestNumber;
        }

        protected int GetRequestNumber(List<KeyValuePair<string, string>> tags, string subject)
        {
            if (this.RequestTypes == null)
            {
                this.RequestTypes = new RequestManagementFacade().GetAllRequestTypes();
            }

            return ExtractRequestNumber(this.RequestTypes, tags, subject);
        }

        public void AssociateFromSlack()
        {
            bool isValid;
            List<SlackClient.MessagesFromSlack> messages = new List<SlackClient.MessagesFromSlack>();
            var getParamBuilder = this.slackClient.GetParams(this.form["text"].Split(' '), this.form["response_url"], out isValid, this.form["user_id"]);
            if (!isValid)
            {
                return;
            }

            dynamic response = JsonConvert.DeserializeObject(this.slackClient.GetChannelsHistory(this.form["channel_id"], getParamBuilder.ToString()));
            var extractRequestNumber = this.GetRequestNumber(null, this.form["channel_name"].ToUpper());
            var requestNumber = new RequestBroker().FindByNumber(extractRequestNumber);
            if (requestNumber == null)
            {
                this.slackClient.SlackMessageTemplate(this.form["response_url"], "The request you are trying to associate does not exist.");
                return;
            }
            else
            {
                messages = this.slackClient.GetAllChat(response);
            }

            if (String.IsNullOrEmpty(this.apiKey))
            {
                this.slackClient.SlackMessageTemplate(this.form["response_url"], "Please enter a MSM Api Key.");
                return;
            }
            else if (messages != null && !messages.Any())
            {
                this.slackClient.SlackMessageTemplate(this.form["response_url"], "No Messages were added. Please enter valid parameters, etc: /associate xxxxxxxxxxxxxxxx xxxxxxxxxxxxxxxx");
                return;
            }
            else
            {
                if (this.noteType.Equals("1") || this.noteType.Equals("2"))
                {
                    dynamic responseAssociatedUser = JsonConvert.DeserializeObject(this.slackClient.GetUserInfo(this.form["user_id"]));
                    var content = this.slackClient.AddNotes(responseAssociatedUser, messages);
                    var data = new Dictionary<string, string>();
                    data.Add("Content", content);
                    data.Add("Type", this.noteType);
                    using (var client = new WebClient())
                    {
                        try
                        {
                            client.Encoding = Encoding.UTF8;
                            client.Headers.Add(HttpRequestHeader.Authorization, "Bearer " + this.apiKey);
                            client.Headers.Add(HttpRequestHeader.ContentType, "application/json");
                            client.UploadString(String.Format(this.baseNoteUrl, requestNumber.Identifier), "POST", JsonConvert.SerializeObject(data));
                            this.slackClient.SlackMessageTemplate(this.form["response_url"], "Messages were added to notes successfully.");
                        }
                        catch (Exception e)
                        {
                            this.slackClient.SlackMessageTemplate(this.form["response_url"], "Please check global settings: " + e.Message);
                        }
                    }
                }
                else
                {
                    this.slackClient.SlackMessageTemplate(this.form["response_url"], "Note Type not configured. Please contact your MSM administrator.");
                    return;
                }
            }
        }
    }

    public class SlackClient
    {
        private readonly Uri baseUri;
        private string apiKey;
        private Dictionary<string, string> data;

        public SlackClient(string baseUrl, string apiKey)
        {
            this.apiKey = apiKey;
            this.baseUri = new Uri(baseUrl);
        }

        public string PostMessage(string channelId, Payload payload)
        {
            payload.Channel = channelId;
            string payloadJson = JsonConvert.SerializeObject(payload);
            return this.CreateMessage(this.baseUri + "chat.postMessage", payloadJson, "POST");
        }

        public string GetChannelsHistory(string channelId, string filters)
        {
            return this.ProcessRequest(this.baseUri + string.Format("channels.history?channel={0}{1}", channelId, filters), "GET");
        }

        public string GetUserInfo(string userId)
        {
            return this.ProcessRequest(this.baseUri + string.Format("users.info?user={0}&include_locale=true", userId), "GET");
        }

        public StringBuilder GetParams(string[] parameters, string responseUrl, out bool isValid, string userId)
        {
            isValid = true;
            StringBuilder paramBuilder = new StringBuilder();
            if (!string.IsNullOrEmpty(parameters[0]))
            {
                dynamic responseUser = JsonConvert.DeserializeObject(this.GetUserInfo(userId));
                var startDate = DateTime.MinValue;
                var endDate = DateTime.MinValue;
                DateTime.TryParseExact(parameters[0], "yyyy.MM.dd.HH:mm:ss", null, DateTimeStyles.None, out startDate);
                if (parameters.Length > 1)
                {
                    DateTime.TryParseExact(parameters[1], "yyyy.MM.dd.HH:mm:ss", null, DateTimeStyles.None, out endDate);
                }

                var validationErrors = string.Empty;
                if (startDate == DateTime.MinValue)
                {
                    validationErrors += String.Format("Start date was not in the correct format i.e {0}.", DateTime.UtcNow.ToString("yyyy.MM.dd.HH:mm:ss"));
                    isValid = false;
                }

                if (parameters.Length > 1 && endDate == DateTime.MinValue)
                {
                    validationErrors += String.Format("\r\nEnd date was not in the correct format i.e {0}.", DateTime.UtcNow.ToString("yyyy.MM.dd.HH:mm:ss"));
                    isValid = false;
                }

                if (!string.IsNullOrEmpty(validationErrors))
                {
                    this.SlackMessageTemplate(responseUrl, validationErrors);
                }
                else
                {
                    startDate = startDate.AddSeconds(-(int)responseUser.user.tz_offset.Value);
                    paramBuilder.Append(string.Format("&oldest={0}", this.ToUnixTimeSeconds(startDate)));
                    if (endDate != DateTime.MinValue)
                    {
                        endDate = endDate.AddSeconds(-(int)responseUser.user.tz_offset.Value);
                        paramBuilder.Append(string.Format("&latest={0}", this.ToUnixTimeSeconds(endDate)));
                    }
                }
            }

            return paramBuilder;
        }

        private Int32 ToUnixTimeSeconds(DateTime dateTime)
        {
            return (Int32)(dateTime.Subtract(new DateTime(1970, 1, 1))).TotalSeconds;
        }

        public List<MessagesFromSlack> GetAllChat(dynamic response)
        {
            List<MessagesFromSlack> listOfMessages = new List<MessagesFromSlack>();
            Dictionary<string, string> colourForUser = new Dictionary<string, string>();
            foreach (var message in response.messages)
            {
                var random = new Random();
                var colourType = String.Format("#{0:X6}", random.Next(0x1000000));
                if (message.subtype == null)
                {
                    dynamic responseUserRealName = JsonConvert.DeserializeObject(this.GetUserInfo(message.user.Value));
                    if (!colourForUser.ContainsKey(responseUserRealName.user.id.Value)) colourForUser.Add(responseUserRealName.user.id.Value, colourType);
                    listOfMessages.Add(new SlackClient.MessagesFromSlack()
                    {
                        text = message.text,
                        user = responseUserRealName.user.real_name.Value,
                        ts = message.ts,
                        colour = colourForUser.ContainsKey(responseUserRealName.user.id.Value) ? colourForUser[responseUserRealName.user.id.Value] : colourType
                    });
                }
            }

            return listOfMessages;
        }

        public string AddNotes(dynamic response, List<MessagesFromSlack> getListFromMethod)
        {
            string content = string.Format("<p><b><i>Associated By: {0} </i></b></p>", response.user.real_name.Value);
            string template = "<div><p><span style=\"color: {0};\">{1} ({2}):</span> {3} </p></div>";
            foreach (var message in getListFromMethod)
            {
                DateTime dateTime = new DateTime(1970, 1, 1, 0, 0, 0, 0);
                dateTime = dateTime.AddSeconds(Convert.ToDouble(message.ts.Substring(0, 10)));
                var timestamp = dateTime.ToLongDateString() + " - " + dateTime.ToShortTimeString() + " UTC";
                content += string.Format(template, message.colour, message.user, timestamp, message.text);
            }

            return content;
        }

        public string WebhookToSlack(string url, string data, string method)
        {
            return this.ProcessRequest(url, data, method);
        }

        public void SlackMessageTemplate(string responseUrl, string message)
        {
            data = new Dictionary<string, string> {{"text",  message}};
            this.WebhookToSlack(responseUrl, JsonConvert.SerializeObject(data), "POST");
        }

        public string DoesChannelExist(string channelName, dynamic response)
        {
            string channelId = string.Empty;
            foreach (var channel in response.channels.ToObject<List<dynamic>>())
            {
                if (channel.name.Value == channelName.ToLower())
                {
                    channelId = channel.id.Value;
                }
            }

            return channelId;
        }

        public string CreateMessage(string url, string data, string method)
        {
            return this.ProcessRequest(url, data, method);
        }

        public string CreateChannel(string url, string name, string method)
        {
            name = name.ToLower();
            data = new Dictionary<string, string> {{"name",  name}};
            var response = this.ProcessRequest(url, JsonConvert.SerializeObject(data), method);
            var responseObject = JsonConvert.DeserializeObject<dynamic>(response);
            return responseObject.channel.id;
        }

        public dynamic GetAllChannels()
        {
            var response = this.ProcessRequest(this.baseUri + string.Format("conversations.list"), null);
            dynamic slack = JsonConvert.DeserializeObject<dynamic>(response);
            return slack;
        }

        private string ProcessRequest(string uri, string body = null, string method = "GET")
        {
            using (WebClient client = new WebClient())
            {
                client.Headers.Add(HttpRequestHeader.Authorization, "Bearer " + this.apiKey);
                client.Headers.Add(HttpRequestHeader.ContentType, "application/json");
                if (method == "GET")
                {
                    return client.UploadString(uri, method);
                }
                else
                {
                    return client.UploadString(uri, method, body);
                }
            }
        }

        public class Payload
        {
            [JsonProperty(PropertyName = "response_type", NullValueHandling = NullValueHandling.Ignore)]
            public string ResponseType { get; set; }

            [JsonProperty(PropertyName = "channel", NullValueHandling = NullValueHandling.Ignore)]
            public string Channel { get; set; }

            [JsonProperty(PropertyName = "username", NullValueHandling = NullValueHandling.Ignore)]
            public string Username { get; set; }

            [JsonProperty(PropertyName = "text", NullValueHandling = NullValueHandling.Ignore)]
            public string Text { get; set; }

            [JsonProperty(PropertyName = "attachments", NullValueHandling = NullValueHandling.Ignore)]
            public Attachment[] Attachments { get; set; }

            public class Attachment
            {
                [JsonProperty(PropertyName = "fallback", NullValueHandling = NullValueHandling.Ignore)]
                public string Fallback { get; set; }

                [JsonProperty(PropertyName = "title", NullValueHandling = NullValueHandling.Ignore)]
                public string Title { get; set; }

                [JsonProperty(PropertyName = "text", NullValueHandling = NullValueHandling.Ignore)]
                public string Text { get; set; }

                [JsonProperty(PropertyName = "actions", NullValueHandling = NullValueHandling.Ignore)]
                public Action[] Actions { get; set; }

                [JsonProperty(PropertyName = "callback_id", NullValueHandling = NullValueHandling.Ignore)]
                public string CallbackId { get; set; }

                [JsonProperty(PropertyName = "attachment_type", NullValueHandling = NullValueHandling.Ignore)]
                public string AttachmentType { get; set; }

                [JsonProperty(PropertyName = "color", NullValueHandling = NullValueHandling.Ignore)]
                public string Color { get; set; }

                [JsonProperty(PropertyName = "fields", NullValueHandling = NullValueHandling.Ignore)]
                public field[] fields { get; set; }

                public class field
                {
                    [JsonProperty(PropertyName = "title", NullValueHandling = NullValueHandling.Ignore)]
                    public string Title { get; set; }

                    [JsonProperty(PropertyName = "short", NullValueHandling = NullValueHandling.Ignore)]
                    public bool Short { get; set; }

                    [JsonProperty(PropertyName = "value", NullValueHandling = NullValueHandling.Ignore)]
                    public string Value { get; set; }
                }
            }

            public class Action
            {
                [JsonProperty(PropertyName = "name", NullValueHandling = NullValueHandling.Ignore)]
                public string Name { get; set; }

                [JsonProperty(PropertyName = "text", NullValueHandling = NullValueHandling.Ignore)]
                public string Text { get; set; }

                [JsonProperty(PropertyName = "type", NullValueHandling = NullValueHandling.Ignore)]
                public string Type { get; set; }

                [JsonProperty(PropertyName = "value", NullValueHandling = NullValueHandling.Ignore)]
                public string Value { get; set; }

                [JsonProperty(PropertyName = "url", NullValueHandling = NullValueHandling.Ignore)]
                public string Url { get; set; }

                [JsonConverter(typeof(StringEnumConverter))]
                public enum ActionType
                {
                    Button
                }
            }
        }

        public class MessagesFromSlack
        {
            public string text { get; set; }
            public string user { get; set; }
            public string ts { get; set; }
            public string colour { get; set; }
        }

        public class SlashCommandPayload
        {
            public string token { get; set; }
            public string team_id { get; set; }
            public string team_domain { get; set; }
            public string enterprise_id { get; set; }
            public string enterprise_name { get; set; }
            public string channel_id { get; set; }
            public string channel_name { get; set; }
            public string user_id { get; set; }
            public string user_name { get; set; }
            public string command { get; set; }
            public string text { get; set; }
            public string response_url { get; set; }
            public string trigger_id { get; set; }
        }
    }
}
