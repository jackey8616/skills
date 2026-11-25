/** Shorten a title for the sidebar. */
export function shortTitle(title: string): string {
  // The sidebar fits about 40 characters.
  return title.length > 40 ? title.slice(0, 39) + "…" : title;
}

export function logTitle(title: string): void {
  // eslint-disable-next-line no-console
  console.log(shortTitle(title));
}
