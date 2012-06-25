#!/bin/zsh
emulate zsh

MAINHOST=carbon

BACKUP_ROOT=/backup

inc(){
    print 'Making snapshot...'
    e=inc
    btrfs subvolume snapshot $last $f.$e
}
new(){
    print 'Making subvolume...'
    e=new
    btrfs subvolume create $f.$e
}

TRAPZERR(){
    print BACKUP FAILED
    [[ -e $f ]] && print 'partial backup in '$f
    exit 2
}

# $1 is type of backup, 'inc' or 'new'
# if not given, do inc if existing backup, otherwise new
if [[ $1 != (|inc|new) ]]; then
    print 'usage: $0:t [inc|new]'
    exit 1
fi

# ensure hostname
h=${HOST:?}

# where this backup will be placed
d=${BACKUP_ROOT}/${h}
# name of this backup
# hostname and ISO8601 date+time
n=${h}-$(date +'%Y%m%dT%H%M')

# working path template for this backup
f=$d/.$n
# final path template for this backup
backup=$d/$n

if [[ -e $(print $backup.*(N)) ]]; then
    print $backup exists
    exit 1
elif [[ -e $(print $f.*(N)) ]]; then
    print Partial backup at $f.*
    exit 1
fi

# path to most recent existing backup
# N -- no error message if no matches
# n -- sort numerically
# On -- sort by name descending
# [1] -- first match only
# ^D -- turn off GLOB_DOTS
last=$(print ${d}/${h}-*(NnOn[1]^D))

print 'BACKING UP '$n

if [[ -z $last ]]; then
    print -l '*** no existing backup found ***'
    if [[ $1 == inc ]]; then
        exit 1
    else
        new
    fi
else
    print 'previous backup: '$last:t
    if [[ $1 == (|inc) ]]; then
        inc
    else
        read -q '?Make fresh (not incremental) backup (y/n)? ' || exit
        new
    fi
fi
RSYNC_LOG=$(mktemp)
print 'Syncing...'
/usr/bin/rsync -i --del --delete-excluded --exclude-from=/backup.exclude --archive --numeric-ids --hard-links --inplace --acls --xattrs --one-file-system --stats --omit-dir-times / $f.$e/ |& tee $RSYNC_LOG
print 'Finalizing...'
mv -i $f.$e $backup.$e
mv -i $RSYNC_LOG $backup.$e/backup.log
if [[ ${h} == $MAINHOST ]]; then
    id=$(btrfs subvolume list $BACKUP_ROOT | fgrep $n.$e | cut -f2 -d' ')
    print 'Setting default snapshot '$id
    btrfs subvolume set-default $id $BACKUP_ROOT
fi
print 'Done'

