#[derive(Copy, Drop, Serde, Default, PartialEq, starknet::Store)]
pub struct Book {
    id: u8,
    title: felt252,
    author: felt252,
}

#[starknet::interface]
pub trait IBookStore<TContractState> {
    fn add_book(ref self: TContractState, title: felt252, author: felt252);
    fn remove_book(ref self: TContractState, id: u8);
    fn borrow_book(ref self: TContractState, id: u8);
    fn return_book(ref self: TContractState, id: u8);
    fn get_books(self: @TContractState) -> Array<Book>;
    fn get_book(self: @TContractState, id: u8) -> Book;
    // NEW FUNCTIONS ADDED
    fn get_total_books(self: @TContractState) -> u8;
    fn update_book_title(ref self: TContractState, id: u8, new_title: felt252);
    fn transfer_storekeeper(ref self: TContractState, new_storekeeper: ContractAddress);
}

#[starknet::contract]
pub mod SkillupBookStore {
    use starknet::event::EventEmitter;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use super::{Book, IBookStore};

    #[storage]
    pub struct Storage {
        pub storekeeper: ContractAddress,
        pub books: Map<u8, Book>,
        pub lent_books: Map<ContractAddress, Book>,
        pub book_counter: u8
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        BookBorrowed: BookBorrowed,
        BookReturned: BookReturned,
        BookAdded: BookAdded,
        RemovedBook: RemovedBook,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BookBorrowed {
        book_id: u8,
        borrower: ContractAddress,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BookReturned {
        pub book_id: u8,
        pub borrower: ContractAddress,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BookAdded {
        pub book_id: u8,
        pub book_title: felt252,
        pub book_author: felt252,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RemovedBook {
        pub book_id: u8,
        pub timestamp: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, storekeeper: ContractAddress) {
        self.storekeeper.write(storekeeper);
        self.book_counter.write(1);
    }

    #[abi(embed_v0)]
    pub impl SkillupBookStoreImpl of IBookStore<ContractState> {
        fn add_book(ref self: ContractState, title: felt252, author: felt252) {
            let caller = get_caller_address();
            let storekeeper = self.storekeeper.read();
            assert(caller == storekeeper, 'Caller not permitted');

            let book_id = self.book_counter.read();
            self.book_counter.write(book_id + 1);

            let book = Book { id: book_id, title, author };

            self.books.entry(book_id).write(book);

            let timestamp = get_block_timestamp();

            self.emit(BookAdded { book_id, book_title: title, book_author: author, timestamp });
        }

        fn remove_book(ref self: ContractState, id: u8) {
            assert(get_caller_address() == self.storekeeper.read(), 'Caller not permitted');
            let existing_book = self.books.entry(id).read();

            assert(existing_book != Default::default(), 'Book does not exist');

            self.books.entry(id).write(Default::default());
            self.emit(RemovedBook { book_id: id, timestamp: get_block_timestamp() });
        }

        fn borrow_book(ref self: ContractState, id: u8) {
            let caller = get_caller_address();

            let already_borrowed_book = self.lent_books.entry(caller).read();
            assert(already_borrowed_book == Default::default(), 'Caller holds a book already');

            let existing_book = self.books.entry(id).read();
            assert(existing_book != Default::default(), 'Book does not exist');

            self.lent_books.entry(caller).write(existing_book);

            self
                .emit(
                    BookBorrowed {
                        book_id: id, borrower: caller, timestamp: get_block_timestamp(),
                    },
                );
        }

        fn return_book(ref self: ContractState, id: u8) {
            let caller = get_caller_address();

            let borrowed_book = self.lent_books.entry(caller).read();
            let the_book = self.books.entry(id).read();
            assert(the_book == borrowed_book, 'Returning wrong book');
            assert(borrowed_book != Default::default(), 'Caller did not borrow a book');

            self.lent_books.entry(caller).write(Default::default());

            self
                .emit(
                    BookReturned {
                        book_id: id, borrower: caller, timestamp: get_block_timestamp(),
                    },
                );
        }

        fn get_books(self: @ContractState) -> Array<Book> {
            let mut all_books_array = array![];
            let book_counter = self.book_counter.read();

            for i in 1..book_counter {
                let current_book = self.books.entry(i).read();
                all_books_array.append(current_book);
            }

            all_books_array
        }

        fn get_book(self: @ContractState, id: u8) -> Book {
            let existing_book = self.books.entry(id).read();
            assert(existing_book != Default::default(), 'Book does not exist');
            existing_book
        }

        // NEW FUNCTION 1: READ FUNCTION - Returns total number of books
        fn get_total_books(self: @ContractState) -> u8 {
            self.book_counter.read() - 1
        }

        // NEW FUNCTION 2: WRITE FUNCTION - Updates a book's title
        fn update_book_title(ref self: ContractState, id: u8, new_title: felt252) {
            let caller = get_caller_address();
            let storekeeper = self.storekeeper.read();
            assert(caller == storekeeper, 'Caller not permitted');

            let mut existing_book = self.books.entry(id).read();
            assert(existing_book != Default::default(), 'Book does not exist');

            existing_book.title = new_title;
            self.books.entry(id).write(existing_book);
        }

        // NEW FUNCTION 3: WRITE FUNCTION - Transfers storekeeper role to new address
        fn transfer_storekeeper(ref self: ContractState, new_storekeeper: ContractAddress) {
            let caller = get_caller_address();
            let current_storekeeper = self.storekeeper.read();
            assert(caller == current_storekeeper, 'Caller not permitted');
            
            self.storekeeper.write(new_storekeeper);
        }
    }
}
