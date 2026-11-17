import type { Note } from "./types.ts";

const shortBody = `Monday, after the standup.

Maya is blocked on the billing export. I told her I would look at the CSV parser tonight and send notes before Wednesday's review.

We decided to ship the CSV fix on Friday and hold the PDF export until the parser stops dropping the last row.

I still owe Luis a reply about the contractor invoice. Keep that out of the shared channel. The amount is fine, but the date on the invoice is wrong.

Personal reminder: pick up the prescription after work. Do not put that on the team board.`;

const longBody = `Field notes from the Saturday conversation with Ruth Ellison at the East Branch library. Ruth has run the Saturday desk for eleven years. She asked that we not print her home phone in the newsletter.

The branch lost the Sunday hours in March. Ruth says the people who feel it most are the tax-prep volunteers and the two students who use the upstairs tables because their apartment is too loud. She wants Sunday back from noon to four, even if the desk is volunteer-run.

Printer situation: the public printer jams on anything heavier than normal paper. A replacement quote from Harbor Office came in at $640, which is over the branch supply budget. Ruth thinks the Friends of the Library could cover it if we ask before their December meeting. She will not ask herself. She wants the board to send the note.

Programs people actually come to: the Thursday reading hour is full, the resume clinic is half full, and the evening coding class was cancelled after three weeks because the instructor moved. Do not schedule another coding class until we have a person who can commit through May.

Building: the north window leaks when the wind comes off the river. A bucket lives under it. Ruth has reported it twice. The last reply she got was that facilities would look in the spring. She would like something in writing before winter.

Quotes to keep, in her words: "People treat a closed Sunday like a small thing. It is the only day some of them can get here." And: "I am not asking for a new building. I am asking for the door to be open and the printer to work."

Next steps I promised her: draft the Friends funding note for the printer, put Sunday hours on the board agenda, and send facilities one more leak report with the date of the first one attached. I told her I would not mention her phone number and I would show her the draft before it goes to the board.

She also mentioned that the book drop fills up by noon on Saturday and that two of the holds from last week were sent to the west branch by mistake. That is a separate operations issue. Park it until the hours question is settled.

Parking lot, so it is not lost: the children's area rug was rolled up after the leak in February and never put back. The Saturday crossword group wants the table by the window, which is the same table the tax volunteers use in March. Ruth thinks a written schedule on the door would stop the argument. She also asked whether the board minutes can stop listing volunteer last names. I said I would check before the next packet goes out.`;

export function starterNotes(now = Date.now()): Note[] {
  return [
    {
      id: "monday-standup",
      title: "Monday standup",
      body: shortBody,
      createdAt: now - 86_400_000,
      updatedAt: now,
      brief: null,
      lastRun: null,
    },
    {
      id: "library-interview",
      title: "East Branch interview",
      body: longBody,
      createdAt: now - 172_800_000,
      updatedAt: now - 60_000,
      brief: null,
      lastRun: null,
    },
  ];
}
