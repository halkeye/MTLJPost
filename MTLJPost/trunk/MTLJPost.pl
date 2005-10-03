# Title:        MT-LJPost
# URL:          http://www.halkeye.net/projects/index.cgi?project=1 
# Summary:      A plugin for posting to livejournal whenever you post/edit an entry to MOveable Type
# Author:       Gavin Mogan (halkeye@halkeye.net) (http://www.halkeye.net/)
# Version:      1.9.1
#
# History
# 1.0.0 - January 29, 2004
#  - Inital Release
# 1.0.1 - January 30, 2004
#  - Removing needing so many variables
#  - Adding selecting of which blog you want.
#
# 1.0.2 - January 30, 2004
#  - Added config file because I got tired of always having to change the file for release
#      this file goes into your mt directory, not plugins (for now, i'll fix it next version or something)
#  # Format: blogid site username password
#  #         3 www.livejournal.com test test
#  #         4 www.deadjournal.com:90 test test
#  - Added handler to check for LJ::Simple and give a message without it
#
# 1.0.3 - January 30, 2004
#  - Entries will now edit after the inital post.
#  - If an entry doesn't save to livejournal, just hit save again
#  - Added support for exerpts / lj-cut
#  - Date of LJ post is date of Actual Entry. You'll have to watch out for backdated entries
#      If its a problem, set the date to now, post, then reset to old.
#      Temp Fix
#  - Convert Line Breaks actually working.
#
# 1.0.4 - January 30, 2004
#  - Date fix, oooopsies
#
# 1.0.5 - Febuary 09, 2004
#  - Started some hooks for MT Plugin Manager
#  - Cleaned up some error messages
#  - Disabled comments
#  - Deletes from livejournal when entry is deleted from MT
#  - Web interface to do configuration /mt-ljpost.cgi
#
# 1.6 - April 03, 2004
#  - Changed version schema
#  - Fixed problem when lj times out but data is still stored so you can no longer edit old entries.
#  - Added Template support (for entries, subjects are still not)
#  - MANY BUG fixes
#
# 1.7 - April 17, 2004
#  - Massive amount of bug fixes yet again (sorry all)
#  - User pic stuff
#  - Yea.. Requirement of LJ::Simple 0.11
#
# 1.7.1 - April 18, 2004 
#  - Ignore Drafts
#  - Disable UTF as it was crapping out on certain links i was posting?
#
# 1.7.2 - April 24, 2004
#  - Added Category flag to output (suggestion from fiercepoet.com)
#
# 1.8.0 - March 22, 2005
#  - Cleaned up a bit more to work with MT 3.x (tested with 3.15)
# 1.8.1 - April 01, 2005
#  - bug fix for MT 3.x deleting
# 1.9.0 - August 01, 2005
#  - Updating on comments and %commentcount%
#  - Moved  all templates inline
#  - Cleaned up config pages
#  - errors now goto the error log instead of killing the entry save
#  - fixed timestamp error todo with timezones and such.
# 1.9.1 - August 09, 2005
#  - Updateing on trackbacks and %trackbackcount%
# 1.9.2 - Sept 23, 2005
#  - Fixed up rebuild all entries
#  - Error messages are recorded internally
#
# Information about this plugin can be found at
# http://www.halkeye.net/projects/index.cgi?project=1
#
# Requires the LJ::Simple perl module - http://www.bpfh.net/computing/software/LJ%3a%3aSimple/
# Or CPAN as i prefer.
#
# Copyright 2004 - 2005 Gavin Mogan
# This code cannot be redistributed without
# permission from the author. 

package MT::Plugin::MTLJPost;
use warnings;
use strict;

my ($MT_DIR, $PLUGIN_DIR, $PLUGIN_ENVELOPE);
BEGIN {
   eval {
      require File::Basename; import File::Basename qw( dirname );
      require File::Spec;

      $MT_DIR = $ENV{PWD};
      $MT_DIR ||= dirname($0)
      if !$MT_DIR || !File::Spec->file_name_is_absolute($MT_DIR);
      $MT_DIR = dirname($ENV{SCRIPT_FILENAME}) 
      if ((!$MT_DIR || !File::Spec->file_name_is_absolute($MT_DIR)) 
         && $ENV{SCRIPT_FILENAME});
      unless ($MT_DIR && File::Spec->file_name_is_absolute($MT_DIR)) {
         die "Plugin couldn't find own location";
      }
   }; if ($@) {
      print "Content-type: text/html\n\n$@"; 
      exit(0);
   }

   $PLUGIN_DIR = $MT_DIR;
   ($MT_DIR, $PLUGIN_ENVELOPE) = $MT_DIR =~ m|(.*[\\/])(plugins[\\/].*)$|i;
   $MT_DIR ||= $PLUGIN_DIR;

   unshift @INC, $MT_DIR . 'lib';
   unshift @INC, $MT_DIR . 'extlib';
}

use Digest::MD5 qw(md5_hex);
use HTML::Template;
use LJ::Simple;
use POSIX qw(mktime difftime);
use Data::Dumper;

use MT;
use MT::App;
use MT::App::CMS;
use MT::Blog;
use MT::Entry;
use MT::Category;
use MT::Comment;
use MT::PluginData;
use MT::Permission;
use MT::Trackback;
use MT::Util qw(dirify encode_html);
use vars qw( $VERSION $ERRORMESSAGE);
$VERSION = '1.9.2';
$ERRORMESSAGE = undef;
{
        # Trap ugly redefinition warnings
        local $SIG{__WARN__} = sub {  }; 

        my $mt_callback_error = \&MT::ErrorHandler::error;
        *MT::ErrorHandler::error = sub {
           my $msg = $_[1] || '';
           $msg .= "\n" unless $msg =~ /\n$/;
           $ERRORMESSAGE = $msg;
           return $mt_callback_error(@_);
        }
}
 
my $ljtag = eval { require MT::Plugins::MTLJTag; 1 } ? 1 : 0;

my $plugin = undef;
my $doc_link = "http://kodekoan.com/projects/mtplugins/MTLJPost/$VERSION/";
# comment, category, template and author.
eval{ require MT::Plugin };
unless ($@) {
   my $plugin_dir = "$MT_DIR/plugins/MTLJPost";
	$plugin = new MT::Plugin();
	$plugin->name("MTLJPost");
	$plugin->description("Duplicates Posts to livejournal. VERSION: $VERSION");
	$plugin->doc_link($doc_link);
   if (-e $plugin_dir && -d _ ) {
      $plugin->config_link("../../mt.cgi?__mode=mtljpost_configall");
      MT->add_plugin_action('blog', '../../mt.cgi?__mode=mtljpost_cfg', 'Configure MTLJPost Login Information');
      MT->add_plugin_action('blog', '../../mt.cgi?__mode=mtljpost_categories', 'Configure MTLJPost Categories');
      MT->add_plugin_action('blog', '../../mt.cgi?__mode=mtljpost_post', 'Repost all entries to livejournal');
   }
   else {
      $plugin->config_link("../mt.cgi?__mode=mtljpost_configall");
      MT->add_plugin_action('blog', '../mt.cgi?__mode=mtljpost_cfg', 'Configure MTLJPost Login Information');
      MT->add_plugin_action('blog', '../mt.cgi?__mode=mtljpost_categories', 'Configure MTLJPost Categories');
      MT->add_plugin_action('blog', '../mt.cgi?__mode=mtljpost_post', 'Repost all entries to livejournal');
   }
	MT->add_plugin($plugin);
   
   MT::App::CMS->add_methods(
      'mtljpost_configall' => \&configure_all,
      'mtljpost_cfg' => \&configure_blog_ljlogin,
      'mtljpost_manager' => \&lj_post_manage,
      'mtljpost_categories' => \&configure_blog_ljcategories,
      'mtljpost_post' => \&ljpost_repost,
   );

   MT::Entry->add_callback( "post_save",   10, $plugin, \&cb_MTLJPostEntrySave );
   MT::Entry->add_callback( "pre_remove", 10, $plugin, \&cb_MTLJPostEntryRemove );
   MT::Comment->add_callback( "post_save",   10, $plugin, \&cb_MTLJPostCommentSave );
   MT::Comment->add_callback( "pre_remove", 10, $plugin, \&cb_MTLJPostCommentRemove );
   MT::Trackback->add_callback( "post_save",   10, $plugin, \&cb_MTLJPostTrackbackSave );
   MT::Trackback->add_callback( "pre_remove", 10, $plugin, \&cb_MTLJPostTrackbackRemove );
}
else {
   die "You really need to upgrade to MT 3.x for this version, or use an earlier version";
}

sub cb_MTLJPostCommentSave 
{
   my ($eh,$comment) = @_;
   return &cb_MTLJPostEntrySave($eh, MT::Entry->load($comment->entry_id));
}

sub cb_MTLJPostCommentRemove 
{
   my ($eh,$comment) = @_;
   return &cb_MTLJPostEntryRemove($eh, MT::Entry->load($comment->entry_id));
}

sub cb_MTLJPostTrackbackSave 
{
   my ($eh,$comment) = @_;
   return &cb_MTLJPostEntrySave($eh, MT::Entry->load($comment->entry_id));
}

sub cb_MTLJPostTrackbackRemove 
{
   my ($eh,$comment) = @_;
   return &cb_MTLJPostEntryRemove($eh, MT::Entry->load($comment->entry_id));
}

sub cb_MTLJPostEntrySave 
{
   my ($eh, $entry) = @_;
   my $errstr = '';

   my $blog = MT::Blog->load($entry->blog_id);
   my $logindata = get_login($entry->blog_id);
   return 1 unless (defined $logindata and $logindata->{'enabled'});
   return 1 if $entry->status ne MT::Entry::RELEASE();
   my $category = $entry->category || MT::Category->load($entry->category_id);

   my $lj = new LJ::Simple ({
         user    => $logindata->{'username'},
         pass    => $logindata->{'password'},
         site    => $logindata->{'site'},
         pics    => 1,
      });

   return $eh->error("Failed to log into LiveJournal:" . $LJ::Simple::error) unless defined $lj;

   # Build up the subject
   my $subject = '';
   $subject .= $blog->name . ": " if ($logindata->{'site_subject'});
   $subject .= $entry->title;

   my $t = HTML::Template->new_scalar_ref(\$logindata->{'format'},
      filter => sub { my $text_ref = shift; $$text_ref =~ s/\%(.*?)\%/<TMPL_VAR NAME="$1">/g; },
      die_on_bad_params=>0) or return $eh->error("Template Error");

   MT::Plugins::MTLJTag::tagify(0) if $ljtag;
   my $body = MT->apply_text_filters($entry->text, $entry->text_filters);
   $t->param('EXCERPT', $body);
   if ( defined $entry->text_more && $entry->text_more ne "") {
      $body .= "<lj-cut>\n";
      $body .= MT->apply_text_filters($entry->text_more, $entry->text_filters);
      $body .= "</lj-cut>";
   }
   MT::Plugins::MTLJTag::tagify(1) if $ljtag;

   $t->param('ENTRY', $body);
   $t->param('ENTRY_ID', $entry->id);
   if ($category) {
      $t->param('CATEGORY', $category->label);
      $t->param('CATEGORY_ID', $category->id);
      $t->param('CATEGORY_DESCRIPTION', $category->description);
      $t->param('CATEGORY_HTMLNAME', MT::Util::dirify($category->label));
   }
   $t->param('SITE_URL', $blog->site_url);
   $t->param('BLOG_NAME', $blog->name);
   $t->param('PERMALINK', $entry->permalink);
   $t->param('COMMENTCOUNT', $entry->comment_count);
   $t->param('TRACKBACKCOUNT', $entry->trackback_count);

   my $time_t = - ( $entry->modified_on - $entry->created_on );

   my $event=();

   my $data = get_entry_data($entry->blog_id, $entry->id);
   my %Event=();
   # yes this is code duplication
   if (defined $data)
   {
      my $itemid = $data->{'itemid'} || 0;
      (defined $lj->GetEntries(\%Event, undef, "one", $itemid )) || return $eh->error("Failed to get Previous Entry: " . $LJ::Simple::error . "\n");
      $event = (values %Event)[0] || undef;
      unless (defined $event) {
         return $eh->error("Can't find Entry: $itemid");
         $data = undef;
         delete_entry_data($entry->blog_id, $entry->id);
         $lj->NewEntry(\%Event) || return $eh->error("Failed to create new entry: " . $LJ::Simple::error . "\n");
         $event = \%Event;
      }
   }
   else
   {
      $lj->NewEntry(\%Event) || return $eh->error("Failed to create new entry: " . $LJ::Simple::error . "\n");
      $event = \%Event;
   }
   my $pic=$lj->Getprop_picture_keyword($event);
   my $cat_pic = $logindata->{categories}->{MT::Util::dirify($category->label || '')} if ($category);

   my %pictures;
   $lj->pictures(\%pictures);
   if (defined $category and defined $cat_pic and (!defined $pic or $pic eq "")) { 
      $lj->Setprop_picture_keyword($event, $cat_pic) or
      return $eh->error("Failed to set picture: " . $LJ::Simple::error . "\n");
   }
   $lj->SetEntry($event,$t->output) || return $eh->error("Failed to set entry: " . $LJ::Simple::error . "\n");
   $lj->SetSubject($event,$subject) || return $eh->error("Failed to set subject: " . $LJ::Simple::error . "\n");
   $lj->Setprop_preformatted($event, 1) if ($entry->convert_breaks);
   $lj->Setprop_preformatted($event, 0) unless ($entry->convert_breaks);
   $lj->SetDate($event,$time_t) || return $eh->error("Failed to set date: " . $LJ::Simple::error . "\n");       
   $lj->Setprop_backdate(\%Event, 0);
   if (!defined $data) {
      # 3600 Seconds gives you an hour window to post it properly, otherwise it gets marked as back dated and you have to manually fix it.
      $lj->Setprop_backdate(\%Event, 1) if (($entry->modified_on-$entry->created_on) >= 3600);
      my ($item_id,$anum,$html_id) = $lj->PostEntry($event);
      (defined $item_id) or return $eh->error("$0: Failed to post journal entry: " . $LJ::Simple::error . "\n");
      my %entry_data;
      $entry_data{'itemid'} = $item_id;
      $entry_data{'lastupdated'} = localtime();
      save_entry_data($entry->blog_id, $entry->id,\%entry_data);
   } 
   else {
      $lj->EditEntry($event) or
      return $eh->error("Failed to edit entry: " . $LJ::Simple::error);
      $data->{'lastupdated'} = localtime();
      save_entry_data($entry->blog_id, $entry->id,$data);
   }
}

sub cb_MTLJPostEntryRemove 
{
   my ($eh, $entry) = @_;
   my $errstr = '';

   my $blog = MT::Blog->load($entry->blog_id);
   my $logindata = get_login($entry->blog_id);
   return 1 if (not defined $logindata or not $logindata->{'enabled'});

   my $lj = new LJ::Simple ({
         user    => $logindata->{'username'},
         pass    => $logindata->{'password'},
         site    => $logindata->{'site'},
      });

   if (not defined $lj) {
      return $eh->error("Failed to log into LiveJournal:" . $LJ::Simple::error);
   }
   my $data = get_entry_data($entry->blog_id, $entry->id);
   if (defined $data) {
      my $itemid = $data->{'itemid'};
      if (not defined $lj->DeleteEntry($itemid)) {
         return $eh->error("Failed to get Delete Entry: " . $LJ::Simple::error . "\n");
      }
      delete_entry_data($entry->blog_id, $entry->id);
   }
}

sub save_entry_data($$$)
{
   my ($blog_id,$entry_id,$data) = @_;
   my $plugin = MT::PluginData->load(
      {
         plugin => 'MTLJPost',
         key    => $blog_id . '_' . $entry_id 
      }
   ) || undef;

   $plugin = MT::PluginData->new unless (defined $plugin);
   $plugin->plugin('MTLJPost');
   $plugin->key($blog_id . '_' . $entry_id);
   $plugin->data($data);
   $plugin->save or die $data->errstr;
}

sub get_login($)
{
   my $blog_id = shift;
   my $data = MT::PluginData->load(
      {
         plugin => 'MTLJPost', 
         key    => $blog_id 
      }
   ) || undef;

   my $logindata;
   $logindata = $data->data if defined $data;
   $logindata = {} unless defined $data;
   my %login = ();
   $login{'site'} = $logindata->{'site'} || 'www.livejournal.com';
   $login{'username'} = $logindata->{'username'} || 'test';
   $login{'password'} = $logindata->{'password'} || 'test';
   $login{'enabled'} = $logindata->{'enabled'} || 0;
   $login{'site_subject'} = $logindata->{'site_subject'} || 0;
   $login{'format'} = $logindata->{'format'} || "%ENTRY%\n<br>\n[<a href=\"%SITE_URL%\">%BLOG_NAME%</a>] \n(<a href=\"%PERMALINK%\">Permanent link to this entry</a>)\n<br />\n";
   $login{categories} = $logindata->{categories} || {};
   # This blog post
   return \%login;
}


sub get_entry_data($$)
{
   my $blog_id = shift;
   my $entry_id = shift;

   my %data;
   my $plugin = MT::PluginData->load(
      {
         plugin => 'MTLJPost',
        key    => $blog_id . "_" . $entry_id 
      }
   ) || undef;
   
   return undef unless defined $plugin;
   
   my $ref = ref($plugin->data);
   if ($ref eq 'SCALAR') {
      my $itemid = $plugin->data;
      $data{'itemid'} = $$itemid;
   }
   else {
      %data = %{$plugin->data};
   }       
   $data{'itemid'} ||= 0;
   $data{'lastupdated'} ||= 'Never';;
   return \%data;
}

sub delete_entry_data($$)
{
   my $blog_id = shift;
   my $entry_id = shift;

   my %data;
   my $plugin = MT::PluginData->load(
      {
         plugin => 'MTLJPost',
         key    => $blog_id . "_" . $entry_id 
      }
   ) || undef;
   return undef unless defined $plugin;
   $plugin->remove();
   return 1;
}

sub configure_all {
   my $app = shift;
   my %plug_Args = @_;
   $app->add_breadcrumb('LJ Post');
   my $template = '<TMPL_INCLUDE NAME="header.tmpl"><div id="cfg-prefs"><p>You must configure each blogs settings individualy. Please goto your blog page for more configuration options.</p></div><TMPL_INCLUDE NAME="footer.tmpl">';
   $app->build_page(\$template,\%plug_Args);
}

sub configure_blog_ljlogin {
   my $app = shift;
   my %param = @_;
   my $blog = MT::Blog->load($app->{query}->param('blog_id')+0) || undef;
   if (!$blog) {
      $app->add_breadcrumb('LJ Post');
      my $errortemplate = '<TMPL_INCLUDE NAME="header.tmpl"><div id="cfg-prefs"><p>Something went wrong, can not find that blog.</p></div><TMPL_INCLUDE NAME="footer.tmpl">';
      $app->build_page(\$errortemplate,\%param);
   }
   if ($app->{query}->param("from") and $app->{query}->param("from") eq "blog_home") {
      $app->add_breadcrumb($blog->name,'mt.cgi?__mode=menu&blog_id=' . $app->{query}->param("blog_id"));
   }
   $app->add_breadcrumb('LJ Post');
   $param{'mtljpost_version'} = $VERSION;
   my $logindata = get_login($blog->id);

   $param{'blog_id'} = $blog->id;
   $param{'lj_site'} = $logindata->{'site'};
   $param{'lj_username'} = $logindata->{'username'};
   $param{'lj_password'} = $logindata->{'password'};
   $param{'lj_format'} = $logindata->{'format'};
   $param{'lj_enabled'} = $logindata->{'enabled'};
   $param{'lj_site_subject'} = $logindata->{'site_subject'};
   $param{'lj_site_subject'} ||= 1;

   if (defined $app->{query}->param('__type'))
   {
      $param{'lj_site'} = $app->{query}->param('lj_site') if defined  $app->{query}->param('lj_site');
      $param{'lj_username'} = $app->{query}->param('lj_username') if defined $app->{query}->param('lj_username');
      $param{'lj_password'} = $app->{query}->param('lj_password') if defined $app->{query}->param('lj_password');
      $param{'lj_format'} = $app->{query}->param('lj_format') if defined $app->{query}->param('lj_format');
      $param{'lj_enabled'} = $app->{query}->param('lj_enabled') || 0;
      $param{'lj_site_subject'} = $app->{query}->param('lj_site_subject') || 0;

      # step 2 now, go and list categories with drop down boxes for each of the userpics.
      {
         my $lj = new LJ::Simple ({
               user    => $param{'lj_username'},
               pass    => $param{'lj_password'},
               site    => $param{'lj_site'},
            });

         $param{'errmsg'} = $LJ::Simple::error unless (defined $lj);
         if (defined $lj)
         {
            my $message = $lj->message() || "Success";
            $message =~ s/(http|ftp|https|telnet):\/\/(\S+)/<a href=\"$1\:\/\/$2\">$2<\/a>/g;
            $param{'loginmsg'} = $message;
         }
      }
      my $data = MT::PluginData->load({ plugin => 'MTLJPost',
            key    => $blog->id }) || undef;
      $data = MT::PluginData->new unless (defined $data);
      $logindata->{'enabled'} = $param{'lj_enabled'};
      $logindata->{'username'} = $param{'lj_username'};
      $logindata->{'password'} = $param{'lj_password'};
      $logindata->{'site'} = $param{'lj_site'};
      $logindata->{'format'} = $param{'lj_format'};
      $logindata->{'site_subject'} = $param{'lj_site_subject'};
      $data->plugin('MTLJPost');
      $data->key($blog->id);
      $data->data($logindata);
      $data->save or ($param{'errmsg'} .= $data->errstr);
   }
   my $template = <<ENDOFTEMPLATE;
<TMPL_INCLUDE NAME="header.tmpl">
<!-- Begin main content -->

<script language="javascript" type="text/javascript">
  function setstatus(value) {
         document.settings.site_subject.disabled=value;
         document.settings.lj_username.disabled=value;
         document.settings.lj_password.disabled=value;
         document.settings.lj_site.disabled=value;
         document.settings.lj_format.disabled=value;
         document.settings.lj_test.disabled=value;
  }
  function updatestatus() {
          if (document.settings.lj_username.disabled == false) {
                  setstatus(true);
          }
          else {
                  setstatus(false);
          }
  }
</script>
<div id="cfg-prefs">
 <TMPL_IF NAME=MESSAGE>
  <p class="message"><TMPL_VAR NAME=MESSAGE></p>
 </TMPL_IF>

 <p>
  <MT_TRANS phrase="Store your information about your livejournal account here." />
 </p>

 <p>
  <MT_TRANS phrase="For more information, see the" /> <a href="$doc_link"><MT_TRANS phrase="documentation" /></a>.
 </p>

 <form method="post" action="<TMPL_VAR NAME=SCRIPT_URL>" name="settings">
  <!-- <input type="hidden" name="__mode" value="save" /> -->
  <input type="hidden" name="__mode" value="mtljpost_cfg">
  <input type="hidden" name="magic_token" value="<TMPL_VAR NAME=MAGIC_TOKEN>" /> 
  <input type="hidden" name="__type" value="gavin">
  <input type="hidden" name="blog_id" value="<TMPL_VAR NAME=BLOG_ID>">

  <p>
  <TMPL_IF NAME=LJ_ERRMSG>Failed to log into LiveJournal: <span class="error-message"><TMPL_VAR NAME=LJ_ERRMSG></span><br/></TMPL_IF>
  <TMPL_IF NAME=LJ_LOGINMSG>Login Message: <span class="error-message"><TMPL_VAR NAME=LJ_LOGINMSG></span><br/></TMPL_IF>
  <input onclick="updatestatus()" type="checkbox" name="lj_enabled"<TMPL_IF NAME=LJ_ENABLED> value="1" checked</TMPL_IF>> Enabled<br />
  <input type="checkbox" name="lj_site_subject"<TMPL_IF NAME=LJ_SITE_SUBJECT> value="1" checked</TMPL_IF>> Subject With Sitename (EX: "Nameless Blog: New Release" vs "New Release")<br />
  </p>

  <div class="leftcol-full">
   <p>
    <label for="username"><MT_TRANS phrase="Username:"></label><br />
    <input type="text" name="lj_username" id="username" value="<TMPL_VAR NAME=LJ_USERNAME>" />
   </p>
  </div>

  <div class="leftcol-full">
   <p>
    <label for="password"><MT_TRANS phrase="Password:"></label><br />
    <input type="password" name="lj_password" id="password" value="<TMPL_VAR NAME=LJ_PASSWORD>" />
   </p>
  </div>
  
  <div class="leftcol-full">
   <p>
    <label for="site"><MT_TRANS phrase="Site:"></label><br />
    <input type="text" name="lj_site" id="site" value="<TMPL_VAR NAME=LJ_SITE>" />
   </p>
  </div>
  
  <div class="leftcol-full">
   <p>
    <label for="format"><MT_TRANS phrase="Format:"></label><br />
    <textarea cols="50" rows="10" name="lj_format" id="format"><TMPL_VAR NAME=LJ_FORMAT></textarea>
   </p>
  </div>

  <p>
   <input type="submit" value="<MT_TRANS phrase="Update">" onClick="setstatus(false); />
  </p>
 </form>
</div>

<TMPL_INCLUDE NAME="footer.tmpl">
ENDOFTEMPLATE
   $app->build_page(\$template,\%param);
}

sub configure_blog_ljcategories {
   my $app = shift;
   my %param = @_;
   my $blog = MT::Blog->load($app->{query}->param('blog_id')+0) || undef;
   if (!$blog) {
      $app->add_breadcrumb('LJ Post');
      my $template = '<TMPL_INCLUDE NAME="header.tmpl"><div id="cfg-prefs"><p>Something went wrong, can not find that blog.</p></div><TMPL_INCLUDE NAME="footer.tmpl">';
      $app->build_page(\$template,\%param);
   }
   if ($app->{query}->param("blog_id")) {
      $app->add_breadcrumb($blog->name,'mt.cgi?__mode=menu&blog_id=' . $app->{query}->param("blog_id"));
   }
   $param{'mtljpost_version'} = $VERSION;

   $app->add_breadcrumb('LJ Post Categories');
   my $logindata = get_login($blog->id);
        
   %param = %{$logindata};
   $param{'blog_id'} = $blog->id;
        
   # step 2 now, go and list categories with drop down boxes for each of the userpics.
   if (defined $app->{query}->param('save'))
   {
      my @cats = MT::Category->load({ blog_id => $blog->id });
      my ($value, $cat);
      $logindata->{categories} = {};
      foreach my $obj (@cats) {
         $cat = MT::Util::dirify($obj->label);
#         $logindata->{categories}->{"enabled_$cat"} = defined $app->{query}->param('enabled_' . $cat) ? 1 : 0;
         $value = $app->{query}->param('category_' . $cat);
         next if ($value eq '_default');
         $logindata->{categories}->{$cat} = $value;
      }
      my $data = MT::PluginData->load({ plugin => 'MTLJPost',
            key    => $blog->id }) || undef;
      $data = MT::PluginData->new unless (defined $data);
      $data->plugin('MTLJPost');
      $data->key($blog->id);
      $data->data($logindata);
      $data->save or die $data->errstr;
      $logindata = get_login($blog->id);
   }

   {
      my $lj = new LJ::Simple ({
            user    => $param{'username'},
            pass    => $param{'password'},
            site    => $param{'site'},
            pics    => 1,
         });

      $param{'errmsg'} = $LJ::Simple::error unless (defined $lj);
      if (defined $lj)
      {
         my $message = $lj->message() || undef;
         $message =~ s/(http|ftp|https|telnet):\/\/(\S+)/<a href=\"$1\:\/\/$2\">$2<\/a>/g if $message;
         $param{'loginmsg'} = $message;

         my %pictures=();
         my @pictures=();
         $param{'default_icon'} = $lj->DefaultPicURL();
         if (defined $lj->pictures(\%pictures)) {
            my ($keywords,$url)=(undef,undef);
            while(($keywords,$url)=each %pictures) {
               push @pictures, { 
                  keyword=>$keywords, 
                  url=>$url, 
                  htmlkeyword=>$keywords,
                  selected=>0,
               };
            }
            $param{'pictures'} = \@pictures;
         }
      }

      {
         use Storable qw(dclone);
         my @cats = MT::Category->load({ blog_id => $blog->id });
         my @categories;
         foreach my $obj (@cats) {
            my $dirlabel = MT::Util::dirify($obj->label);
            my @pictures = @{ dclone($param{'pictures'})};
            if ( defined $logindata->{categories}->{$dirlabel}) {
               foreach my $pic (@pictures) {
                  $pic->{'selected'} = 1 if ( $logindata->{categories}->{$dirlabel} eq $pic->{'htmlkeyword'});
               }
            }
            push @categories, {id=>$obj->id, description=>$obj->description, label=>$obj->label, htmllabel=>$dirlabel, cat_pictures=>\@pictures};
         }
         $param{'categories'} = \@categories;
      }

   }
   my $template = <<ENDOFTEMPLATE;
<TMPL_INCLUDE NAME="header.tmpl">
<!-- Begin main content -->
<script language="javascript">
  var pictureArray =  new Array(
          "<TMPL_VAR NAME="DEFAULT_ICON">" <TMPL_LOOP NAME=PICTURES>,"<TMPL_VAR NAME=URL>"
  </TMPL_LOOP>); 
          
  function updatePictures() {     <TMPL_LOOP NAME=CATEGORIES>
        document['cat_<TMPL_VAR NAME="HTMLLABEL">_icon'].src = pictureArray[document.settings.category_<TMPL_VAR NAME="HTMLLABEL">.selectedIndex];</TMPL_LOOP>
  }
</script>
<div id="cfg-prefs">
 <TMPL_IF NAME=MESSAGE>
  <p class="message"><TMPL_VAR NAME=MESSAGE></p>
 </TMPL_IF>

 <p>
  <MT_TRANS phrase="Configure MT Category to LJ Icon mapping." />
 </p>

 <p>
  <MT_TRANS phrase="For more information, see the" /> <a href="$doc_link"><MT_TRANS phrase="documentation" /></a>.
 </p>

 <form method="post" action="<TMPL_VAR NAME=SCRIPT_URL>" name="settings">
  <input type="hidden" name="magic_token" value="<TMPL_VAR NAME=MAGIC_TOKEN>" /> 
  <input type="hidden" name="__mode" value="mtljpost_categories">
  <input type="hidden" name="blog_id" value="<TMPL_VAR NAME=BLOG_ID>">

  <p>
  <TMPL_IF NAME=LJ_ERRMSG>Failed to log into LiveJournal: <span class="error-message"><TMPL_VAR NAME=LJ_ERRMSG></span><br/></TMPL_IF>
  <TMPL_IF NAME=LJ_LOGINMSG>Login Message: <span class="error-message"><TMPL_VAR NAME=LJ_LOGINMSG></span><br/></TMPL_IF>
  </p>

<TMPL_LOOP NAME=CATEGORIES>
  <div class="leftcol-full">
    <img style="float: left; margin-right: 10px;" name="cat_<TMPL_VAR NAME="HTMLLABEL">_icon" src="<TMPL_VAR NAME="DEFAULT_ICON">">
<!--   <p>
    <input type="checkbox" name="enabled_<TMPL_VAR NAME="HTMLLABEL">" id="enabled_<TMPL_VAR NAME="HTMLLABEL">"<TMPL_VAR NAME="CAT_ENABLED">>
    <label for="enabled_<TMPL_VAR NAME="HTMLLABEL">">Enabled</label>
   </p> -->
   <p>
    <label for="category_<TMPL_VAR NAME="HTMLLABEL">"><TMPL_VAR NAME="HTMLLABEL">:</label><br />
    <select name="category_<TMPL_VAR NAME="HTMLLABEL">" id="category_<TMPL_VAR NAME="HTMLLABEL">" onChange="updatePictures();">
      <option value="_default">(Default)</option>
      <TMPL_LOOP NAME=CAT_PICTURES><option <TMPL_IF NAME=SELECTED>SELECTED </TMPL_IF>value="<TMPL_VAR NAME="htmlkeyword">" ><TMPL_VAR NAME="keyword"></option>
    </TMPL_LOOP></select>
   </p>
   <br style="clear: both">
  </div>
</TMPL_LOOP>
  
  <p>
   <input name="save" type="submit" value="<MT_TRANS phrase="Update">" />
  </p>
 </form>
</div>

ENDOFTEMPLATE
   $app->build_page(\$template,\%param);
}

sub ljpost_repost {
   my $app = shift;
   my %param = @_;
   my $closestdin = 0;
   my $blog = MT::Blog->load($app->{query}->param('blog_id')+0) || undef;
   if (!$blog) {
      $app->add_breadcrumb('LJ Post');
      my $template = '<TMPL_INCLUDE NAME="header.tmpl"><div id="cfg-prefs"><p>Something went wrong, can not find that blog.</p></div><TMPL_INCLUDE NAME="footer.tmpl">';
      $app->build_page(\$template,\%param);
   }
   if ($app->{query}->param("blog_id")) {
      $app->add_breadcrumb($blog->name,'mt.cgi?__mode=menu&blog_id=' . $app->{query}->param("blog_id"));
   }
   $param{'mtljpost_version'} = $VERSION;

   $app->add_breadcrumb('LJ Post - Reposting all entries');

   my $template = <<ENDOFTEMPLATE;
<TMPL_INCLUDE NAME="header.tmpl">
<div id="cfg-prefs">
 <TMPL_IF NAME=MESSAGE>
  <p class="message"><TMPL_VAR NAME=MESSAGE></p>
 </TMPL_IF>

 <p>
  <MT_TRANS phrase="Repost all entries." />
 </p>

 <p>
  <MT_TRANS phrase="For more information, see the" /> <a href="$doc_link"><MT_TRANS phrase="documentation" /></a>.
 </p>
ENDOFTEMPLATE


   # step 2 now, go and list categories with drop down boxes for each of the userpics.
   if (defined $app->{query}->param('start') and $ENV{'REQUEST_METHOD'} eq 'POST') 
   {
      my %arg = ('sort' => 'created_on', direction => 'descend');
      my $iter = MT::Entry->load_iter({ blog_id => $blog->id,
            status => MT::Entry::RELEASE() },
         \%arg);

      my $msg = '';
      if (my $pid = fork) {
         # redirect to status page
         my @entries =  ();
         my $config = $plugin->get_config_value('resync');
         $config->{complete} = 0;
         $config->{entries} = \@entries;
         $plugin->set_config_value('resync', $config);
      }
      elsif (defined $pid) {
         close STDOUT;
         my @entries =  ();
         my $config = $plugin->get_config_value('resync');
         $config->{complete} = 0;
         $config->{entries} = \@entries;
         $plugin->set_config_value('resync', $config);
         foreach my $entry (MT::Entry->load({ blog_id => $blog->id })) {
           eval { 
               $entry->save(); 
            };
            my $errmsg = $@ ? $ERRORMESSAGE : undef;
            push @entries, { id=>$entry->id, title=>$entry->title, status=>$@ ? "Fail" : "Success", errmsg=>$errmsg};
            $config->{entries} = \@entries;
            $plugin->set_config_value('resync', $config);
         }
         $config->{complete} = 1;
         $plugin->set_config_value('resync', $config);
         return;
      }
      $app->delete_param("start");
      $template .= "[[[REFRESH STATUS PAGE]]]";
      $closestdin = 1;
      my %cgi_params = $app->param_hash;
      $cgi_params{status} = 1;
      $app->redirect($app->uri . "?" . (
            join ";" , map { encode_html($_) . "=" . encode_html($cgi_params{$_}) } keys %cgi_params
         )
      );
   }
   elsif (defined $app->{query}->param('status')) 
   {
      my @entries;
      my $complete = 0;
      if (my $config = $plugin->get_config_value('resync')) {
         @entries = @{$config->{entries}}  if ($config->{entries});
         $complete = 1 if ($config->{complete});
      }
      $param{entries} = \@entries;
      $template .= <<ENDOFTEMPLATE;
      Complete:

<TMPL_LOOP NAME=ENTRIES>
  <div class="leftcol-full">
      Posting Entry ID # <TMPL_VAR NAME=ID> - <TMPL_VAR NAME=TITLE> ... ...
      <b><TMPL_VAR NAME=STATUS></b>
      <TMPL_IF NAME=ERRMSG>
        - <TMPL_VAR NAME=ERRMSG>
      </TMPL_IF>
   <br style="clear: both">
  </div>
</TMPL_LOOP>
ENDOFTEMPLATE

      if ($complete) {
         $template .= "<b> All done</b>";
      }
      else {
         $template .= <<ENDOFTEMPLATE;
<script language="JavaScript">
<!--
var sURL = unescape(window.location.pathname);
setTimeout( "refresh()", 2*1000 );
function refresh() { window.location.href = sURL; }
//-->
</script>
<script language="JavaScript1.1">
<!--
function refresh() { window.location.replace( sURL ); }
//-->
</script>
<script language="JavaScript1.2">
<!--
function refresh() { window.location.reload(false); }
//-->
</script>
ENDOFTEMPLATE
   }


   }
   else {
      $template .= <<ENDOFTEMPLATE;
  <div class="leftcol-full">
   <p>
      This will take some time to do, are you sure you want to do this?
      <form method="post" action="<TMPL_VAR NAME=SCRIPT_URL>" name="settings"><input type="hidden" name="magic_token" value="<TMPL_VAR NAME=MAGIC_TOKEN>" /> <input type="hidden" name="__mode" value="mtljpost_post"><input type="hidden" name="blog_id" value="<TMPL_VAR NAME=BLOG_ID>">
        <input name="start" type="submit" value="<MT_TRANS phrase="Yes">" />
      </form>
      <br style="clear: both">
  </div>
ENDOFTEMPLATE
   }
   $template .= "</div>";
   $app->build_page(\$template,\%param);
}
1;
