-- AlterTable
ALTER TABLE "Meeting" ADD COLUMN     "calendarAttendees" TEXT[],
ADD COLUMN     "calendarEnd" TIMESTAMP(3),
ADD COLUMN     "calendarEventId" TEXT,
ADD COLUMN     "calendarOrganizer" TEXT,
ADD COLUMN     "calendarStart" TIMESTAMP(3),
ADD COLUMN     "calendarTitle" TEXT;
