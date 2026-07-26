/// A single page of a Laravel paginator response — the `data` object
/// returned by any endpoint built on Eloquent's `paginate()`, where the
/// array of items sits at `data.data` alongside `current_page`/`last_page`/
/// `total`. Generic so any future paginated endpoint can reuse it instead
/// of each repository inventing its own pagination wrapper.
class PaginatedResult<T> {
  const PaginatedResult({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  final List<T> items;
  final int currentPage;
  final int lastPage;
  final int total;

  bool get hasMore => currentPage < lastPage;
}
