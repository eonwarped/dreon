* Title: drphil.rb - Voting Bot
* Tags: radiator ruby steem steemdev curation
* Notes: 

#### New Features

* Bug/console output fixes.
* Improved `unique_author` logic to use `account_history` instead of internal timer for improved accuracy between runs.
* Gem update.
* Additional error handling.
* Handling bad json_metadata.

#### Features

* YAML config.
  * `voting_rules`
    * `winfrey` mode that acts like the winfrey bot, all voters vote for everyone
    * `drphil` mode one random voter votes for everyone (default)
    * `following_vote_weight` - for accounts that the voter follows
    * `followers_vote_weight` - for accounts that follow the voter
    * `min_rep` (default `25.0`)
    * `min_wait` and `max_wait` (in minutes) so that you can fine-tune voting delay.
    * `favorite_accounts` list and separate `favorites_vote_weight` option.
      * Note: votes will be cast for favorites irregardless of rep.
    * `enable_comments` option to vote for post replies (default false).
    * `only_first_posts` option to only vote on an author's first post (default false).
    * `max_rep` option, useful for limiting votes to newer authors (default 99.9).
    * `vote_signals` account list.
      * Optionally allows multiple bot instances to cooperate by avoiding vote swarms.
      * If enabled, this feature allows cooperation without sharing keys (in `drphil` mode).
    * `min_rep` can now accept either a static reputation or a dynamic property.
      * Existing static reputation still supported, e.g.: `25.0`
      * Dynamic reputation, e.g.: `dynamic:100`.  This will occasionally query the top 100 trending posts and use the minimum author reputation.
      * Now checking `vote_weight: 0.00 %` and skipping without broadcast.
        * This is useful for special configurations that *only* vote for favorites.
      * `min_voting_power` to create a floor with will allow the voter to recharge over time without having to stop the script.
    * Optionally configure `voters` as a separate filename.  E.g:
      * `voters: voters.txt`
        * The format for the file is just: `account wif` (no leading dash, separated by space)
      * Or continue to use the previous format.
    * Also optional support for separate files in each (format one per line or separated by space or both):
        * `favorite_accounts`
        * `skip_accounts`
        * `skip_tags`
        * `flag_signals`
        * `vote_signals`
    * `only_fully_powered_up` which will only vote for posts that receive 100% STEEM Power author rewards.
* Skip posts with declined payout.
* Skip posts that already have votes from external scripts and posts that were edited.
* Argument called `replay:` allows a replay of *n* blocks allowing you to catch up to the present.
  * E.g.: `ruby drphil.rb replay:90` will replay the last 90 blocks (about 4.5 minutes).
* Thread management
  * Counter displayed so you know what kind of impact `^C` will have.
  * This also keeps the number of threads down when authors edit before Dr. Phil votes.
* Now streaming on Last Irreversible Block Number, just to be fancy.
* Now checking for new HF18 `cashout_time` value (if present).
  * This will skip voting when authors edit their old archived posts.
  * Added `unique_author` (optional) which takes an integer in minutes.  This will limit voting to 1 vote per period.  E.g.: Set it to 1440 to only vote for each author once a day.
  * Added `max_votes_per_post` (optional) which only votes *n* times per post (`winfrey` mode only).
  * Added `only_tags` (optional) which only votes on posts that include these tags.
  * Alternative voting weights all inherit from `vote_weight` if not present.
  * Favorites (`favorite_accounts`) can now have individual vote percent.
    * Formatted as: account:weight (e.g.: `inertia:100.00`)
  * Now checking if any voter can vote at all.  If at least one voter has a non-zero vote_weight, return true.  Otherwise, don't bother to even queue up a new thread, thus saving memory.
  * Argument called `stream:false` will exit without streaming the blockchain.  Useful in situations where you only want to `replay:` and exit.

#### Overview

Dr. Phil (`drphil.rb`) is reimplementation of the "Winfrey" voting bot specification.  The goal is to give everyone an upvote.

One optional improvement is that instead of voting 1% by 100 accounts like the Winfrey bot spec, this script can vote 100% with 1 randomly chosen account.

If the complaint about Winfrey is blockchain bloat, Dr. Phil prescribes weight loss to address this. But this feature would only work if there are enough voters defined in the script.  If you plan to use this script for one or two accounts, you'll probably want to adjust the `VOTE_WEIGHT` constant to something a bit lower.

---

#### Install

To use this [Radiator](https://steemit.com/steem/@inertia/radiator-steem-ruby-api-client) bot:

##### Linux

```bash
$ sudo apt-get update
$ sudo apt-get install ruby-full git openssl libssl1.0.0 libssl-dev
$ sudo apt-get upgrade
$ gem install bundler
```

##### macOS

```bash
$ gem install bundler
```

I've tested it on various versions of ruby.  The oldest one I got it to work was:

`ruby 2.0.0p645 (2015-04-13 revision 50299) [x86_64-darwin14.4.0]`

First, clone this gist and install the dependencies:

```bash
$ git clone https://gist.github.com/61bcc2b821aa5acb24f7fc88921950c7.git drphil
$ cd drphil
$ bundle install
```

Then run it:

```bash
$ ruby drphil.rb
```

Dr. Phil will now do it's thing.  Check here to see an updated version of this bot:

https://gist.github.com/inertia186/61bcc2b821aa5acb24f7fc88921950c7

---

#### Upgrade

Typically, you can upgrade to the latest version by this command, from the original directory you cloned into:

```bash
$ git pull
```

Usually, this works fine as long as you haven't modified anything.  If you get an error, try this:

```
$ git stash --all
$ git pull --rebase
$ git stash pop
```

If you're still having problems, I suggest starting a new clone.

---

#### Troubleshooting

##### Problem: What does this error mean?

```
drphil.yml:1: syntax error, unexpected ':', expecting end-of-input
```

##### Solution: You ran `ruby drphil.yml` but you should run `ruby drphil.rb`.

---

##### Problem: Everything looks ok, but every time Dr. Phil tries to vote, I get this error:

```
Unable to vote with <account>.  Invalid version
```

##### Solution: You're trying to vote with an invalid key.

Make sure the `.yml` file `voter` items have the account name, followed by a space, followed by the account's WIF posting key.  Also make sure you have removed the example accounts (`social` and `bad.account` are just for testing).

##### Problem: The node I'm using is down.

Is there a list of nodes?

##### Solution: Yes, special thanks to @ripplerm.

https://ripplerm.github.io/steem-servers/

---

<center>
  <img src="http://i.imgur.com/qUZYLiQ.png" />
</center>

See my previous Ruby How To posts in: [/f/ruby](https://chainbb.com/f/ruby)

## Get in touch!

If you're using Dr. Phil, I'd love to hear from you.  Drop me a line and tell me what you think!  I'm @inertia on STEEM and [SteemSpeak](http://discord.steemspeak.com).
  
## License

I don't believe in intellectual "property".  If you do, consider Dr. Phil as licensed under a Creative Commons [![CC0](http://i.creativecommons.org/p/zero/1.0/80x15.png)](http://creativecommons.org/publicdomain/zero/1.0/) License.
