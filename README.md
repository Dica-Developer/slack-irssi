# slack-irssi

# Settings

* slack_api_token ('')
Required. Set api token to get access to SLack web api. Token can be received from slack team page.
`/set slack_api_token xoxp-xxxxxxxx-xxxxxxxxx-xxxxxxxxxxxxxxx`

* slack_playback_length (50)
Optional. Defines how many lines to retrive from slack. Defaults to 50. The actual count of lines depends on the history. It can not be guaranteed.
`/set slack_playback_length 100`

* slack_playback_color ('%w')
Optional. Set text and or background color to use when adding history. Possible values can be found [here](https://github.com/shabble/irssi-docs/wiki/Formats#Local-Colours)
`/set slack_playback_color %R`

# Usage
### Playback
To retrive the history of all joined channels just do `/slack playback`. You can add a channel name to get the history just for this channel. `/slack playback #channel`
