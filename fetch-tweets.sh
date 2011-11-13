#!/bin/bash
# Twitter backup script - hendry AT iki.fi - please mail me suggestions to make this suckless
# http://dev.twitter.com/doc/get/statuses/user_timeline
# Known issues:
# API only allows 3200 tweets to be downloaded this way :((
# Won't work on protected accounts (duh!)
# No @mentions or DMs from other accounts

umask 002
api="http://api.twitter.com/1/statuses/user_timeline.xml?"

if ! test "$1"
then
	echo -e "Please specify twitter username\n e.g. $0 kaihendry"
	exit 1
fi

twitter_total=$(curl -s "http://api.twitter.com/1/users/lookup.xml?screen_name=$1" | xmlstarlet sel -t -m "//users/user/statuses_count" -v .)

page=1
saved=0
stalled=0

if test -f $1.txt
then
	saved=$(wc -l $1.txt | tail -n1 | awk '{print $1}')
	since='&since_id='$(head -n1 $1.txt | awk -F"|" '{ print $1 }')
	test "$2" && since='&max_id='$(tail -n1 $1.txt | awk -F"|" '{ print $1 }') # use max_id to get older tweets
fi

while test "$twitter_total" -gt "$saved" # Start of the important loop
do

echo $1 tweet total "$twitter_total" is greater than the already saved "$saved"
echo Trying to get $(($twitter_total - $saved))

temp=$(mktemp)
temp2=$(mktemp)

url="${api}screen_name=${1}&count=200&page=${page}${since}&include_rts=true&trim_user=1&include_entities=1"

echo "curl -s \"$url\""
curl -si "$url" > $temp
echo $?

{
{ while read -r
do
if test "$REPLY" = $'\r'
then
        break
else
        echo "$REPLY" >&2 # print header to stderr
fi
done
cat; } < $temp > $temp2
} 2>&1 | # redirect back to stdout for grep
grep -iE 'rate|status' # show the interesting twitter rate limits
# date --date='@1320361995'

mv $temp2 $temp

if test $(xmlstarlet sel -t -v "count(//statuses/status)" $temp) -eq 0
then   

        head $temp
        if test "$2" && test "$since"
        then   
                echo No old tweets ${since}
        elif test "$since"
        then   
                echo No new tweets ${since}
        else   
                echo "Twitter is returning empty responses on page ${page} :("
        fi
        rm -f $temp $temp2
        exit

fi

xmlstarlet sel -t -m "statuses/status" -n -o "text " -v "text" -m "entities/urls/url" -i "expanded_url != ''" -n -o "url " -v "url" -o " " -v "expanded_url" $temp | {
while read -r first rest
do
        case $first in
                "text") echo $text; text=$rest ;;
                "url")  set -- $(echo $rest); text=$(echo $text | sed s,$1,$2,g) ;;
        esac
done
echo $text
} > $temp2

cat $temp2 | perl -MHTML::Entities -pe 'decode_entities($_)' > $temp
cat $temp | sed '/^$/d' > $temp2

if test -z $temp2
then
	echo $temp2 is empty
	rm -f $temp $temp2
	continue
fi

#cat $temp2

if test -f $1.txt
then
	mv $1.txt $temp
	before=$(wc -l $temp | awk '{print $1}')
else
	before=0
	> $temp
fi

cat $temp $temp2 | sort -r -n | uniq > $1.txt

after=$(wc -l $1.txt | awk '{print $1}')
echo Before: $before After: $after

if test "$before" -eq "$after"
then
	echo Uable to retrieve anything new. Approximately $(( $twitter_total - $after)) missing tweets
	rm -f $temp $temp2
	exit
fi

rm -f $temp $temp2
page=$(($page + 1))
saved=$(wc -l $1.txt | tail -n1 | awk '{print $1}')
echo $saved

done

echo $1 saved $saved tweets of "$twitter_total": You are uptodate!
