# Slack Plugin for MSM

You need to have the slack app installed, a slack account and the slack plugin installed on your MSM.
In Slack, ensure you hace created a workspace and added all required users to it.

## MSM-Slack Integration

This plugin allows you to publish a request's details to a specific workspace in Slack.


## Compatible Versions

| Plugin   | MSM     |
|----------|---------|
| 1.0.1    | 15.11.0 | 
| 1.0.0    | 14.15.0 |
| 1.0.0.22 | 15.1+   |

## Installation

Please see your MSM documentation for information on how to install plugins.

Once the plugin has been installed you will need to configure the following settings within the plugin page:

+ *Slack App OAuth Token*: The OAuth token for authentication with Slack App. You can access this through going to "https://api.slack.com/apps" and first signing in. Then click on your apps name to view its settings, then under "features" go to "OAuth and Permissions" and create a "Bot User OAuth Token".
+ *Enable Mobile Link*: To activate mobile links, set the value to 1 otherwise by default it is deactivated.
+ *MSM API Key*: The MSM APIÿKey is a required field in order to send notes from Slack.
+ *Note Type*: Takes 1 or 2, where 1 is Public and 2 is Private. Notes will not be created from Slack if this field is not populated.

## Usage

The plugin can be launched from the quick menu after you load a request. On clicking the plugin you will be presented with a message "Would you like to publish this request to the Slack channel: INC-XXX?" Choosing No closes the popup with no further action. Choosing Yes creates a new Slack channel with the request type and number as the name e.g. "INC-XXX". The following request information is published to the newly created channel:

+ Request Type and Number with a description e.g. INC-1234 My Email is down. Note: Slack only accepts lower case names, so the incident will be inc-1234.
+ Assignee information.
+ Status information.
+ Links to view the request in Self Service or Service Desk


## Contributing

We welcome all feedback including feature requests and bug reports. Please raise these as issues on GitHub. If you would like to contribute to the project please fork the repository and issue a pull request.
