import Foundation

// MARK: - GraphQL documents
//
// Split out of HardcoverAPI.swift to keep that file under the house line limit. Pure data: the
// request functions that use these live in HardcoverAPI.swift.
extension HardcoverAPI {
    static let searchBooksQuery = """
        query GetBooks($query: String!, $per_page: Int!) {
          search(query: $query, query_type: "book", per_page: $per_page, page: 1) {
            results
          }
        }
        """

    static let insertUserBookMutation = """
        mutation InsertUserBook($book_id: Int!, $status_id: Int!) {
          insert_user_book(object: {book_id: $book_id, status_id: $status_id}) {
            id
          }
        }
        """

    static let bookSeriesQuery = """
        query BookSeries($id: Int!) {
          books(where: {id: {_eq: $id}}, limit: 1) {
            book_series {
              position
              series {
                id
                name
              }
            }
          }
        }
        """

    static let bookDetailsQuery = """
        query BookDetails($id: Int!) {
          books(where: {id: {_eq: $id}}, limit: 1) {
            description
            cached_tags
          }
        }
        """

    static let seriesVolumesQuery = """
        query SeriesBooks($id: Int!) {
          series(where: {id: {_eq: $id}}, limit: 1) {
            book_series(
              distinct_on: position
              order_by: [{position: asc}, {book: {users_count: desc}}]
              where: {
                compilation: {_eq: false}
                book: {canonical_id: {_is_null: true}, is_partial_book: {_eq: false}}
              }
            ) {
              position
              book {
                id
                title
                image { url }
              }
            }
          }
        }
        """

    static let deleteUserBookMutation = """
        mutation DeleteUserBook($id: Int!) {
          delete_user_book(id: $id) {
            book_id
          }
        }
        """
}
