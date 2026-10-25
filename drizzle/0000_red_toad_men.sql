CREATE TABLE `bookmarks` (
	`user_id` text NOT NULL,
	`post_id` text NOT NULL,
	PRIMARY KEY(`user_id`, `post_id`),
	FOREIGN KEY (`user_id`) REFERENCES `profiles`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `groups` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`description` text NOT NULL,
	`color` text DEFAULT 'sage' NOT NULL,
	`icon` text DEFAULT 'users' NOT NULL,
	`owner_id` text,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `groups_name_unique` ON `groups` (`name`);--> statement-breakpoint
CREATE TABLE `knowledge` (
	`id` text PRIMARY KEY NOT NULL,
	`title` text NOT NULL,
	`url` text NOT NULL,
	`content` text NOT NULL,
	`keywords` text NOT NULL,
	`checked_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `memberships` (
	`user_id` text NOT NULL,
	`group_id` text NOT NULL,
	PRIMARY KEY(`user_id`, `group_id`),
	FOREIGN KEY (`user_id`) REFERENCES `profiles`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`group_id`) REFERENCES `groups`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `posts` (
	`id` text PRIMARY KEY NOT NULL,
	`author_id` text NOT NULL,
	`group_id` text NOT NULL,
	`type` text DEFAULT 'Discussion' NOT NULL,
	`title` text NOT NULL,
	`body` text NOT NULL,
	`anonymous` integer DEFAULT false NOT NULL,
	`status` text DEFAULT 'community' NOT NULL,
	`ai_answer` text,
	`ai_mode` text,
	`sources` text DEFAULT '[]' NOT NULL,
	`sample` integer DEFAULT false NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`author_id`) REFERENCES `profiles`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`group_id`) REFERENCES `groups`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `posts_created_idx` ON `posts` (`created_at`);--> statement-breakpoint
CREATE INDEX `posts_group_idx` ON `posts` (`group_id`);--> statement-breakpoint
CREATE TABLE `profiles` (
	`id` text PRIMARY KEY NOT NULL,
	`username` text NOT NULL,
	`stage` text DEFAULT 'Current student' NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `profiles_username_unique` ON `profiles` (`username`);--> statement-breakpoint
CREATE TABLE `replies` (
	`id` text PRIMARY KEY NOT NULL,
	`post_id` text NOT NULL,
	`author_id` text NOT NULL,
	`parent_id` text,
	`body` text NOT NULL,
	`anonymous` integer DEFAULT false NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`author_id`) REFERENCES `profiles`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `replies_post_idx` ON `replies` (`post_id`);--> statement-breakpoint
CREATE TABLE `reports` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`post_id` text NOT NULL,
	`reason` text NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `votes` (
	`user_id` text NOT NULL,
	`post_id` text NOT NULL,
	PRIMARY KEY(`user_id`, `post_id`),
	FOREIGN KEY (`user_id`) REFERENCES `profiles`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON UPDATE no action ON DELETE no action
);
