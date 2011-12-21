/*
 *  This script can be used to HELP find Roadmapping_JournalEntry records.
 *  These occur in the rare event a race condition is triggered in which a
 *  RoadmapItem is removed and also updated/double-removed at the same time,
 *  and later removed again.
 *
 *  We have since closed this race conditions, but on occasion rendering a
 *  Published Roadmap may fail w/a 'Sequence contains no matching element'
 *  error.
 *
 *  This script doesn't directly find such duplicates, but can help you in
 *  limiting the entries to possible duplicates.
 */

select * from [Roadmapping_JournalEntry] as rje where exists
(
  select * from [Roadmapping_JournalEntry] as rje2 where rje2.RoadmapId = rje.RoadmapId and rje2.CommandMessage = rje.CommandMessage
  and rje2.[Id] <> rje.[Id]
)
and rje.CommandMessage like '%RemoveItem%' order by rje.[Id]
