# MTLJPost

Source code for a old movable type plugin that pushed posts to livejournal

## Old readme:

# Installation subheader

1. Extract the archive.
2. Copy the files as neccessary.
  * Make a MTLJPost directory in the plugins directory
  * Copy the MTLJPost.pl file to the plugins/MTLJPost directory
3. Configure it (See Configuration Section)
4. Post

# Configuration

There should be internal menu items for configuring the app.
(i'm trying to remember where from memory and failing)

# Formatting Options

    %EXCERPT% = Body without the extended entry part
    %ENTRY% = whole entry (lj-cut and all)
    %ENTRY_ID% = entry id
    %CATEGORY% = name of category
    %CATEGORY_ID% = ID of category (int)
    %CATEGORY_DESCRIPTION% = description of category
    %CATEGORY_HTMLNAME% = dirified name of category
    %SITE_URL% = Link to your main blog page
    %BLOG_NAME% = Your site name
    %PERMALINK% = Your entries perm link
    %COMMENT_COUNT% = Comments on an entry
    %TRACKBACK_COUNT% = Trackbacks on an entry

# Dependancies

* [LJ::Simple 0.11+](http://search.cpan.org/CPAN/authors/id/S/SI/SIMES/LJ-Simple-0.11.tar.gz)
