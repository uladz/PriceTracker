# PriceTracker

#### General Info
Price Tracker is a simple addon that scans all your guild stores and tracks items and their prices. It then calculates and shows a suggested price on the item tooltip, as well as the minimum and maximum prices and the number of times the item was seen in the stores.

The suggested price can be calculated in several ways (which can be selected in the settings menu):
Average: Simple sum of all prices divided by total number of items.
Median: The price value for which half of the items cost more and half cost less.
Most Frequently Used: The most common price value.
Weighted average: (default) The average price of all items which takes in account "Time Value Of Gold". The latest data gets a weighting of X, where X is the number of days the data covers, thus making newest data worth more. Formula is adapted from Khaibit's Shopkeeper.

#### How to Use:
Initially, all the guild stores have to be inspected in order for the addon to work properly. Simply go to a banker, open the Guild Store menu and click on the 'Scan Prices' button on the left-hand side. This will take a while, depending on how many guild stores are available, and how many items are listed in each guild store. During the scanning process, the 'Scan Prices' button will be disabled. It will be reenabled once all the guild stores have been scanned.

After that, simply select an item in your bag, and if the item is listed in a guild store, it will show the suggested price.

#### Updating Prices
Occasionally, click on the 'Scan Prices' button again to update the price list with newly listed items.
