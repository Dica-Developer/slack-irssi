use diagnostics;
use strict;
use warnings;

our $VERSION = '0.0.1';
our %IRSSI = (
    authors => 'Jörg Weber',
    contact => 'info@dica-developer.org',
    name => 'slack_irssi',
    description => '',
    license => 'GPLv3',
    requires => 'Mozilla::CA, JSON'
);

use Irssi;
use DateTime;
use HTTP::Request::Common qw(POST);
use LWP::UserAgent;
use Data::Dumper;
use JSON;

my $pkg_name = 'slack';
our ($is_slack, @conversations, @users);
our (%chan_name_id, %user_name_id, %user_id_name);

sub set ($) {
    $pkg_name.'_'.$_[0];
}

Irssi::settings_add_int($pkg_name, set('playback_length'), 50);
Irssi::settings_add_bool($pkg_name, set('include_private'), 0);
Irssi::settings_add_str($pkg_name, set('playback_color'), '%w');
Irssi::settings_add_str($pkg_name, set('api_token'), '');
Irssi::settings_add_bool($pkg_name, set('auto_playback'), 0);

Irssi::command_bind('help', 'cmd_help');
Irssi::command_bind("$pkg_name test", \&cmd_test);
Irssi::command_bind("$pkg_name playback", \&cmd_playback);
Irssi::command_bind($pkg_name , \&cmd_handler);
Irssi::signal_add_first("default command $pkg_name", \&cmd_unknown);
Irssi::signal_add_last("server connected", \&kick_off);
Irssi::signal_add_last("complete word", \&completion);

sub show_help {
    my ($help, $text);

    $text='';
    $help = "slack $VERSION
/slack playback
    Retrieves history for all joined channel
/slack playback #<CHANNEL_NAME>
    Retrieves history for given channel
";

    foreach (split(/\n/, $help)) {
        $_ =~ s/^\/(.*)$/%9\/$1%9/;
        $text .= $_."\n";
    }

    print CLIENTCRAP &draw_box('IRSSI Slack', $text, 'slack help', 1);
}

sub cmd_unknown {
    show_help();
    Irssi::signal_stop();
}

sub cmd_help {
    my ($arg, $server, $witem) = @_;

    $arg =~ s/\s+$//;
    show_help() if $arg =~ /^slack/i;
}

sub cmd_playback {
    return unless $is_slack;

    my ($channel, $server, $item) = @_;

    $channel =~ s/^\s+|\s+$//g; #trim whitespaces
    $channel =~ s/#//g; # strip # from channel name

    if ($channel) {
        my $channel_id = $chan_name_id{$channel};
        my @messages = fetch_history($channel_id);

        add_playback($channel, reverse(@messages)) if (scalar @messages);
    } else {
        my @channel_list = Irssi::channels();
        my @channel_names = map{ $_->{name} } @channel_list;

        foreach $channel (@channel_names) {
            my ($channel_id, @messages);

            $channel =~ s/#//g;
            $channel_id = $chan_name_id{$channel};

            next unless $channel_id; #skip private channels

            @messages = fetch_history($channel_id);
            add_playback($channel, reverse(@messages)) if (scalar @messages);
        }
    }
}

sub cmd_handler {
    return unless $is_slack;

    my ($data, $server, $item) = @_;

    $data =~ s/\+s$//g; # strip trailing spaces
    Irssi::command_runsub($pkg_name, $data, $server, $item);
}

sub draw_box {
    my ($title, $text, $footer, $colour) = @_;
    my $box = '';

    $box .= '%R,--[%n%9%U'.$title.'%U%9%R]%n'."\n";

    foreach (split(/\n/, $text)) {
        $box .= '%R|%n '.$_."\n";
    }

    $box .= '%R`--<%n'.$footer.'%R>->%n';
    $box =~ s/%.//g unless $colour;

    return $box;
}

sub make_post {
    my $api = shift;
    my ($request, $ua, $response, $token, %params);

    $token = Irssi::settings_get_str(set('api_token'));

    return if $token eq "";

    %params = ( 'token' => $token );

    if (scalar @_ > 0) {
        my ($k, $v);
        while (($k,$v) = splice(@_, 0, 2)) {
            $params{$k} = $v;
        }
    }

    $request = POST("https://slack.com/api/$api", [ %params ]);

    $ua = LWP::UserAgent->new;
    $response = $ua->request($request);
    return $response->content;
}

sub kick_off {
    my ($server) = @_;
    my $server_addr = $server->{address};

    $is_slack = ($server_addr =~ m/slack/);

    return unless $is_slack;

    my $should_auto_playback = Irssi::settings_get_bool(set('auto_playback'));

    fetch_channels();
    fetch_users();

    #cmd_playback() if $should_auto_playback;
}

sub fetch_users {
    my @args = ('limit', 500);
    my $response = make_post('users.list', @args);
    my $json = decode_json $response;

    @users = @{$json->{members}};
    %user_name_id = map{ $_->{name} => $_->{id} } @users;
    %user_id_name = map{ $_->{id} => $_->{name} } @users;
}

sub fetch_channels {
    my $include_private = Irssi::settings_get_bool(set('include_private'));
    #my $types = $include_private ? 'public_channel,private_channel,mpim,im' : 'public_channel';
    my $types = 'public_channel';
    my @args = ('types', $types, 'exclude_archived', 'true', 'limit', 1000);
    my $response = make_post('conversations.list', @args);
    my $json = decode_json $response;
    @conversations = @{$json->{channels}};

    print CLIENTCRAP &draw_box('Slack Irssi', 'Private messages not implemented yet', 'slack_irssi', 1) if $include_private;

    %chan_name_id = map { $_->{name} => "$_->{id}" } @conversations;
}

sub fetch_history {
    my $channel_id = shift;
    my $limit = Irssi::settings_get_str(set('playback_length'));
    my @args = ('channel', $channel_id, 'limit', $limit);
    my $response = make_post('conversations.history', @args);
    my $json = decode_json($response);

    return @{$json->{messages}};
}

sub add_playback {
    my $channel = shift;
    my $timestamp_format = Irssi::settings_get_str('timestamp_format');
    my $color = Irssi::settings_get_str(set('playback_color'));
    my $win = Irssi::window_item_find("#$channel");
    my $user_regex = "<@(.*?)>";

    foreach my $message (@_) {
        my $timestamp = DateTime->from_epoch(epoch => $message->{ts});
        my $formatted_timestamp = $timestamp->strftime($timestamp_format);
        my $user = $message->{user};
        my $username = $user ? $user_id_name{$user} : 'unknown';
        my $text = $message->{text};
        my @mentions = $text =~ /$user_regex/gi;

        foreach my $user_id (@mentions) {
            my $user_name = $user_id_name{$user_id};

            $text =~ s/$user_regex/\@$user_name/;
        }

        $win->print($color.$formatted_timestamp." ".$username." ".$text.$color);
    }
}

sub completion {
    my ($strings_ref, $window, $word, $linestart) = @_;
    my $is_user = $word =~ /^@/;
    my $is_cmd = $linestart =~ /^\/[M|MSG|Q|QUERY]/i;

    return unless $is_slack && $is_user;

    $word =~ s/^@// if $is_user;

    if ($is_user) {
        my @all_user = keys %user_name_id;
        my @matches = grep(/$word/i, @all_user);
        unless ($is_cmd) {
            for (@matches) { $_ = '@'.$_; };
        }

        @$strings_ref = (@$strings_ref, @matches);
    }

}
