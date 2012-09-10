#!/usr/bin/env ruby
require 'rubygems'
require 'twitter'
require 'json'
require 'faraday'

# things you must configure
PATH_TO_DROPBOX = "/PATH_TO_YOUR_DROPBOX/tweets/" # you must create this folder
TWITTER_USER = "YOUR_USERNAME"

# get these from https://dev.twitter.com/apps
CONSUMER_KEY = "FOO"
CONSUMER_SECRET = "BAR"
OAUTH_TOKEN = "BLEE"
OAUTH_TOKEN_SECRET = "BAZ"

# things you might want to change
MAX_AGE_IN_DAYS = 28 # anything older than this is deleted
DELAY_BETWEEN_DELETES = 0 # in seconds

# you don't really need to mess with this
API_TWEET_MAX = 3200
TWEETS_PER_PAGE = 200 # api max is 250 or something... 200 seems like a nice round number
NUM_PAGES = (API_TWEET_MAX / TWEETS_PER_PAGE).to_i
MAX_AGE_IN_SECONDS = MAX_AGE_IN_DAYS*24*60*60
NOW_IN_SECONDS = Time.now

# fields the script will archive (in addition to media)
FIELDS = [:id,
        :created_at,
        :text,
        :retweet_count,
        :in_reply_to_screen_name,
        :in_reply_to_user_id,
        :in_reply_to_status_id]

# tweet methods

def save_to_dropbox(tweet)
  slender_tweet = {}
  FIELDS.each do |field|
    slender_tweet[field] = tweet[field].to_s
  end
  slender_tweet[:urls] = tweet.urls

  time_string = Time.parse(slender_tweet[:created_at]).to_i.to_s
  file_name = "#{time_string}_#{slender_tweet[:id]}.json"
  full_path = PATH_TO_DROPBOX+file_name
  puts "Saving tweet to #{full_path}"

  f = File.new(full_path,'w')
  f.puts slender_tweet.to_json
  f.close

  # save pictures
  tweet.media.each do |media,i|
    url = media.media_url
    puts "Saving image #{url}"
    http_conn = Faraday.new do |builder|
      builder.adapter Faraday.default_adapter
    end
    response = http_conn.get(url)
    media_path = full_path.gsub(".json","")+"_media_"+File.basename(url)
    File.open(media_path, 'wb') do |f|
      f.write(response.body)
    end
  end
end

def delete_from_twitter(tweet)
  begin
    Twitter.status_destroy(tweet.id)
  rescue
    puts "Error saving #{tweet.id}"
  else
    puts "Deleted"
  end
end

# init twitter

Twitter.configure do |config|
  config.consumer_key = CONSUMER_KEY
  config.consumer_secret = CONSUMER_SECRET
  config.oauth_token = OAUTH_TOKEN
  config.oauth_token_secret = OAUTH_TOKEN_SECRET
end

# begin script

puts ""
puts "What's that sound...?"
puts ""

timeline = []

error_count = 0

NUM_PAGES.times do |i|
  begin
    puts "Requesting tweets #{i*TWEETS_PER_PAGE}-#{(i+1)*TWEETS_PER_PAGE}"
    timeline = timeline.concat(Twitter.user_timeline(TWITTER_USER,{:count=>TWEETS_PER_PAGE,:page=>i,:include_entities=>true,:include_rts=>true}))
  rescue
    error_count += 1
    if (error_count > 5) then
      puts "Too many errors! Try again later."
      exit
    else
      puts "Error getting tweets, retrying after #{2**error_count} seconds..."
      sleep(2**error_count)
      retry
    end
  end
end

puts "Got #{timeline.size} tweets"
puts ""

timeline.each do |tweet|
  tweet_age = NOW_IN_SECONDS - tweet.created_at

  if (tweet_age < MAX_AGE_IN_SECONDS) then
    puts "Ignored a tweet #{(tweet_age/(24*60*60)).round} days old"
  else
    puts "Preparing to delete a tweet #{(tweet_age/(24*60*60)).round} days old"

    begin
      save_to_dropbox(tweet)
    rescue
      puts "Error saving #{tweet.id}"
    else
      delete_from_twitter(tweet)
    end
  end

  puts "  #{tweet.text}"
  puts ""

  sleep DELAY_BETWEEN_DELETES
end

puts "Done! Remaining API reqs this hour: #{Twitter.rate_limit_status.remaining_hits.to_s}"