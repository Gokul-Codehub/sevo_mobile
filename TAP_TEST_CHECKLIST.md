# Storefront tap checklist (run on a real phone before every release)

Rule: a CATEGORY always opens the category page (sub-categories left, products right). A PRODUCT always opens its product page.

## Home page
- [ ] Every category tile / circle opens the category page - including a category with ONE product (e.g. Laundry Additive).
- [ ] The category page shows the sibling sub-categories in the left rail and the selected one's products on the right.
- [ ] Every product card / product banner opens the product page directly (no category page in between).
- [ ] A banner linked to a category opens the category page; a banner linked to a product opens the product page.
- [ ] Bestseller tiles open the category page.
- [ ] "See all products" opens the category page.

## Category page
- [ ] Tapping a sub-category with deeper levels drills in; the back arrow goes up one level.
- [ ] Tapping a product opens the product page; back returns to the same sub-category and scroll position.
- [ ] A category with one product shows a one-item rail and that product.
- [ ] An out-of-area location shows "We do not deliver here yet".

## Product page
- [ ] Pack sizes switch price, image and stock on the same page.
- [ ] Add to Cart works; cart shows the same line.
- [ ] Back goes to where you came from.

## Also check after any change to navigation
- [ ] Deep link / notification into a category and into a product.
- [ ] Search result -> product, search result -> category.
- [ ] Order again / recently viewed -> product page.
