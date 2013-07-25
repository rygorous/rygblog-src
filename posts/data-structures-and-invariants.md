-title=Data structures and invariants
-time=2010-09-27 09:18:59
Enough bit\-twiddling for now, time to talk about something a bit more substantial: Invariants. If you don't know what that is, an invariant is just a set of conditions that will hold before and after every "step" of your program/algorithm. This is usually taught in formal CS education, but textbooks love to focus on invariants in *algorithm* design. That's fine for the types of algorithms typically found \(and analyzed\) en masse in CS textbooks: sorting, searching, and basic graph algorithms. But it has little relevance to the type of problems you usually encounter in applications, where you don't encounter nice abstract problems with well\-defined input and output specifications, but a tangled mess of several \(often partially conflicting\) requirements that you have to make sense of. So most programmers forget about invariants pretty soon and don't think about them again.

That's a mistake. Invariants are a very useful tool in practice, *if* you have a clear specification of what's supposed to happen, and how. That may not be the case for the whole of the program, but it's usually the case for the part of your code that manipulates data structures. Let me give you some examples:

### Example 1: A singly\-linked list.

```cpp
struct ListNode {
  ListNode *next;
  // other data...
};

ListNode *head = NULL; // Head pointer (empty list at start)
```

You should be familiar with this. A singly\-linked list is a very simple data structure: You keep a pointer to the first element and every element stores a pointer to its successor. Typically \(in C anyway\), a `NULL` pointer is used to denote the end of the list, and setting `head` to `NULL` denotes an empty list.

So what are the invariants? None, it turns out. If you have a pointer to the first element and every element has a pointer to the next element, you have a singly\-linked list. This makes singly\-linked list fairly easy to manipulate. For example, setting `head = head->next;` will remove the first element from the list. But actually, all you need to identify a singly\-linked list uniquely is a pointer to its first element. If you want an algorithm to work on all but the first element, you just pass `head->next` instead of `head` \(this is used heavily in functional languages\). There's no easy way to remove some element `x` from the list directly, but you can easily remove an element given its predecessor `p`: Just set `p->next = p->next->next;`. Adding a new element at the front is almost as simple, except we need to update two pointers instead of one:

```cpp
void AddAtFront(ListNode *x)
{
  x->next = head; // Next element is the previous head of the list
  head = x; // We're the new head
}
```

Adding a new node at the back, however, forces you to traverse the whole list from beginning to end. You can avoid this by keeping a second pointer to the last element added, and updating it accordingly:

### Example 2a: A singly\-linked list with tail \(version 1\)

```cpp
// ListNode as above
ListNode *head = NULL; // We still keep the head pointer
ListNode *tail = NULL; // And now a tail too
```

How does this affect our algorithms? Working out the details, it turns out that the operations we discussed previously all get more complicated as a result of this addition:

```cpp
void RemoveFirst()
{
  head = head->next;
  if (!head) tail = NULL; // Removing last element is special
}

void RemoveNext(ListNode *x)
{
  x->next = x->next->next;
  if (!x->next) tail = x; // We're the new last element
}

void AddAtFront(ListNode *x)
{
  x->next = head; // Next element is the previous head of the list
  if (!head) tail = x; // List used to be empty, we're the new tail!
  head = x; // We're the new head
}

void AddAtBack(ListNode *x)
{
  x->next = NULL; // This'll be the new end!
  if (!head)
    head = x; // First element is special!
  else
    tail->next = x; // Add after tail
  tail = x; // We're the new tail!
}

// Explanation follows below
bool IsInList(ListNode *x)
{
  ListNode *cur = head;
  // Look for our item, abort at end of list
  while (cur != x && cur)
    cur = cur->next;
  return cur == x;
}
```

And suddenly there's special\-case handling in every single of these functions. Also note that we suddenly need two pointers \(head and tail\) to describe our linked list, *and they need to agree*. Lo and behold, our first invariant: For a pair \(head,tail\) to denote a valid singly\-linked list with tail pointer, we require that either:

* `!head && !tail` \(the list is empty\)
* or `head && IsInList(tail) && !tail->next` \(the list isn't empty, tail is in the list, and no element follows it \- i.e. it is indeed the last one\).

IsInList is a simple predicate \(=boolean function, if you will\) that traverses the list and checks whether some element is indeed inside it. If you wanted to write an Unit Test, these are things you should check after every test: These properties *must* hold or our augmented singly\-linked list is internally inconsistent. This is because `tail` is nothing but a cached value. It could in principle be recomputed from `head` every time we need it, but that would make things slower. We cache it to win back speed, but that means we need to do extra work to keep head and tail in sync. This is a typical pattern in data structures: Whenever your data structure has multiple ways of reaching the same data \(in this case, either through the "head" or "tail" pointers\), you get an invariant that you need to maintain: both "views" must be consistent with each other.

Also, there's two separate cases in our invariant: The `head == NULL` case is special, and if you look at the code above, you'll notice that we indeed treat it specially in several places. That's a hint: If we modify our data structure to make the invariant simpler, the code itself might get simpler too. The trick in this case turns out to be not storing `tail`, but `&tail->next`: The "next" pointer for the last element. Even for an empty list, this is always well\-defined: if `head == NULL`, then `head` itself is the "next" pointer we need. Putting this idea to work leads to:

### Example 2b: A singly\-linked list with tail \(version 2\)

```cpp
// ListNode again the same
ListNode *head = NULL;
ListNode **tailNext = &head; // Instead of tail!

void RemoveFirst()
{
  head = head->next;
  if (!head) tailNext = &head; // Last element is special
}

void RemoveNext(ListNode *x)
{
  x->next = x->next->next;
  if (!x->next) tailNext = &x->next; // New last element!
}

void AddAtFront(ListNode *x)
{
  x->next = head; // Next element is the previous head of the list
  if (!head) tailNext = &x->next; // New last element!
  head = x; // We're the new head
}

void AddAtBack(ListNode *x)
{
  x->next = NULL; // This'll be the new end!
  *tailNext = x; // Add after tail
  tailNext = &x->next; // We're the new tail
}

// Modification of IsInList that checks if x is a valid
// "predecessor next pointer" in the list.
bool IsValidNext(ListNode **x)
{
  ListNode *cur = head, **prevNext = &head;
  // Look for our item, abort at end of list
  while (prevNext != x && cur) {
    prevNext = &cur->next;
    cur = *prevNext;
  }
  return prevNext == x;
}
```

Not hugely different, but it's a bit less code in `AddAtBack`, and the "keep a pointer to the next pointer of the previous element" idiom turns out to be useful when writing singly\-linked list code in general. In particular, every function that modifies "head" can be changed to get a "prevNext" pointer and modify that instead, turning operations that only work on the start of the list to operations that work everywhere. Doing this to "RemoveFirst" and "AddAtFront" turns the two into an alternative implementation of RemoveNext and a general "add element after some existing element in this list", respectively. Anyway, after this modification, our new invariant is:

* `IsValidNext(tailNext) && *tailNext == NULL` \(tailNext is the "next" pointer of some element in the list, and that element is indeed the last one\)

Which is a lot cleaner, even though IsValidNext is a tad more complicated than IsInList was. On to the next example \- let's take things up a notch and look at a data structure with extra pointers per node, rather than just on the outside. This get a lot more complicated \(and interesting\) there.

### Example 3a: A doubly\-linked list \(naive version\)

I'm just gonna give you the declaration for now, and then we'll look right at the invariants we need to maintain:

```cpp
struct DListNode {
  DListNode *prev, *next; // Our two links per node
  // ...payload here
};

DListNode *head = NULL, *tail = NULL;
```

So what are the invariants here? Let's go through them:

* If `head == NULL`, then `tail == NULL` \(empty list\)
* If `head != NULL`, then `IsInList(head, tail) && !head->prev && !tail->next`. Furthermore:
    <br>
* If `head != NULL`, then *for every element* `x != tail` in the list, `x->next->prev == x` \(prev/next pointers agree\)

Some of these can be replaced with their symmetric counterparts. For example, instead of checking that `tail` is reachable from `head` by following `next` pointers, you can also check that `head` is reachable from `tail` by following `prev` pointers. And similarly, you can reverse the direction and test that `x->prev->next == x` for every `x != head`. All of these modified invariants are equivalent.

There's two things to note about this: First, we now have one invariant *per element*, in addition to a few "global" ones. And all of these better hold, because otherwise you have a list that contains different elements depending on the direction in which you traverse it. Secondly, there sure is a lot of special\-casing going on now. We have special cases for empty lists as well as the first and last elements of a list. If you've ever written a doubly\-linked list like that, you know that this is pretty painful in the code. That's why I don't give an example, because there's a better way to handle things. The trick from before doesn't really help here; what you really need to do to restore sanity is introduce a dummy \("sentinel"\) element per list in front of the actual head, so that "empty" lists still contain one element \(the sentinel\). That gets rid of all the special cases for `head == NULL`. You can use the same trick on the tail too and add another sentinel element at the end, but now you need two dummy elements per list. There's a second trick to reduce that overhead: Make your doubly\-linked lists circular. Then the sentinel can be both "before" the `head` element and "after" the `tail` element \(in fact, your head and tail pointers are now `sentinel.next` and `sentinel.prev`, respectively\). This has the same amount of overhead as a single sentinel would and leads to much cleaner \(and simpler\) code.

### Example 3a: A doubly\-linked list \("proper" version\)

```cpp
// DListNode as above
DListNode list; // Sentinel: init to list.next = list.prev = &list;
```

Now, what are the invariants here? Let's see:

* For every element `x` in the list \(including the sentinel!\), `x->next->prev == x` \(or equivalently `x->prev->next == x`\).

And that's it. No special rules for the first or last elements and no special case for the empty list. We still have one invariant per element, but that's all invariants we need to maintain. The corresponding code is very clean, too:

```cpp
bool IsEmpty() // Just for illustration
{
  return list.next == &list;
}

void InsertAfter(DListNode *p, DListNode *x) // Insert x after p
{
  // First x's prev/next pointers correctly
  x->prev = p;
  x->next = p->next;
  // Then actually add it to the list
  x->prev->next = x;
  x->next->prev = x;
}

void Remove(DListNode *x) // Remove x from the list it's in
{
  x->prev->next = x->next; // Make our predecessor skip x
  x->next->prev = x->prev; // Our successor too
}
```

This is less than half as much code as you'd have without the sentinel element, and it's way easier to get right. It still has twice the amount of pointer manipulations as the singly\-linked case, though \(as you would expect, it being a doubly\-linked list\). Note that you do this extra work solely to maintain the invariants; if you had a large block of code that does lots of list manipulation and only ever traverses the list front\-to\-back and doesn't need the "prev" pointers, you could only update the "next" pointers for a while \(effectively treating the list as singly\-linked\), and then go through the list once at the end to fix all the "prev" pointers once you're done.

For a doubly\-linked list this is hardly useful \(since they're still fairly simple data structures\), but for more complicated data structures \(with more invariants being maintained\), this approach starts to get appealing.

More complicated data structures have more complicated invariants. Binary trees with a "left" and "right" child pointer don't have any special invariant you need to maintain \(just like singly\-linked lists\). Once you add a "parent" pointer, you get the invariant that `x->left->parent == x && x->right->parent == x` \(if those kids exist\) for each node in the tree. That's why most textbook implementations of binary trees don't have parent pointers. One step further, binary search trees have a key per element, and require that each element in the left subtree of `x` has a key smaller than `x->key`, and every element in the right subtree of `x` has a key larger than `x->key`. This is fairly easy to satisfy during insertion but requires quite some gymnastics to maintain on deletion. Further down the line of "classic" CS data structures, there's balanced trees, which come in several flavors. The most well\-known are probably AVL trees and Red\-Black \(RB\) trees, both spin\-offs on binary search trees that guarantee $$O(log N)$$ time per operation for a tree with $$N$$ elements. AVL's guarantee is better than the one for RB trees: in AVL trees, the height of two subtrees always differs by at most 1, while RB trees can lean quite a bit to one side. But since the AVL invariant is stronger, it's also more work to maintain \(and requires a larger set of local tree modifications than RB\-trees do\). If you've ever implemented either of these buggers, you know that this is all fairly tricky to get right \- for that very reason, most people who have to implement this tend to base their code heavily off example code from textbooks.

Anyway, consider this an introduction to the topic. This is actually going somewhere, but I wanted to set the ground first with some simple examples. Next up: Some nontrivial data structures I've had to deal with, their invariants, and how thinking about them changed my perspective significantly.
