import { integer, sqliteTable, text, primaryKey, index } from "drizzle-orm/sqlite-core";

export const profiles = sqliteTable("profiles", {
  id: text("id").primaryKey(),
  username: text("username").notNull().unique(),
  stage: text("stage").notNull().default("Current student"),
  createdAt: integer("created_at").notNull(),
});
export const groups = sqliteTable("groups", {
  id: text("id").primaryKey(), name: text("name").notNull().unique(),
  description: text("description").notNull(), color: text("color").notNull().default("sage"),
  icon: text("icon").notNull().default("users"), ownerId: text("owner_id"),
  createdAt: integer("created_at").notNull(),
});
export const memberships = sqliteTable("memberships", {
  userId: text("user_id").notNull().references(() => profiles.id),
  groupId: text("group_id").notNull().references(() => groups.id),
}, (t) => [primaryKey({ columns: [t.userId, t.groupId] })]);
export const posts = sqliteTable("posts", {
  id: text("id").primaryKey(), authorId: text("author_id").notNull().references(() => profiles.id),
  groupId: text("group_id").notNull().references(() => groups.id),
  type: text("type").notNull().default("Discussion"), title: text("title").notNull(), body: text("body").notNull(),
  anonymous: integer("anonymous", { mode: "boolean" }).notNull().default(false),
  status: text("status").notNull().default("community"),
  aiAnswer: text("ai_answer"), aiMode: text("ai_mode"), sources: text("sources").notNull().default("[]"),
  sample: integer("sample", { mode: "boolean" }).notNull().default(false),
  createdAt: integer("created_at").notNull(),
}, (t) => [index("posts_created_idx").on(t.createdAt), index("posts_group_idx").on(t.groupId)]);
export const replies = sqliteTable("replies", {
  id: text("id").primaryKey(), postId: text("post_id").notNull().references(() => posts.id),
  authorId: text("author_id").notNull().references(() => profiles.id),
  parentId: text("parent_id"), body: text("body").notNull(),
  anonymous: integer("anonymous", { mode: "boolean" }).notNull().default(false),
  createdAt: integer("created_at").notNull(),
}, (t) => [index("replies_post_idx").on(t.postId)]);
export const votes = sqliteTable("votes", {
  userId: text("user_id").notNull().references(() => profiles.id),
  postId: text("post_id").notNull().references(() => posts.id),
}, (t) => [primaryKey({ columns: [t.userId, t.postId] })]);
export const bookmarks = sqliteTable("bookmarks", {
  userId: text("user_id").notNull().references(() => profiles.id),
  postId: text("post_id").notNull().references(() => posts.id),
}, (t) => [primaryKey({ columns: [t.userId, t.postId] })]);
export const reports = sqliteTable("reports", {
  id: text("id").primaryKey(), userId: text("user_id").notNull(),
  postId: text("post_id").notNull().references(() => posts.id),
  reason: text("reason").notNull(), createdAt: integer("created_at").notNull(),
});
export const knowledge = sqliteTable("knowledge", {
  id: text("id").primaryKey(), title: text("title").notNull(),
  url: text("url").notNull(), content: text("content").notNull(),
  keywords: text("keywords").notNull(), checkedAt: text("checked_at").notNull(),
});
