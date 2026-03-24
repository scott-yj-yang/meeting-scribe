export interface CreateMeetingInput {
  title: string;
  date: string;
  duration: number;
  audioSources: string[];
  meetingType?: string;
  rawMarkdown: string;
  segments: {
    speaker: string;
    text: string;
    startTime: number;
    endTime: number;
  }[];
}
