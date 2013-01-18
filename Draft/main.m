/* @author Jeremy W. Sherman
 * @date 2012-12-22
 * @license OSI MIT License
 *
 * Draft is a proof of concept that GCD queue-specific values
 * could be used as a rudimentary prototype-based object system.
 *
 * (Draft also happens to be the prototype of a written dispatch.) */
#import <Foundation/Foundation.h>
#import <search.h>

#define draft_log(fmt, ...) \
    do { /*fprintf(stderr, fmt "\n", ## __VA_ARGS__);*/ } while (0)

/* The underlying object type is a dispatch queue. */
typedef dispatch_queue_t draft_t;

/* All slots are a binary block. */
typedef draft_t (^draft_slot_t)(draft_t me, draft_t you);

/* New objects are created by cloning an existing one. */
draft_t draft_clone(draft_t parent) OS_OBJECT_RETURNS_RETAINED;

/* Sets a slot on an object to a value. */
void draft_set(draft_t obj, const char *slot, draft_slot_t val);

/* Sends a message to an object. */
draft_t draft_send(draft_t obj, const char *msg, draft_t other);

/* Relays a message up the chain. */
draft_t draft_super(draft_t obj, const char *msg, draft_t other);

/* Returns the root object. */
draft_t draft_object(void);

int main(int argc, const char * argv[])
{

    @autoreleasepool {
        printf("root object is %p\n", draft_object());

        /* The value of a number is the number of links in its
         * parent chain till you hit |zero|. */
        draft_t zero = draft_clone(draft_object());
        printf("zero is %p\n", zero);

        /* Add a successor function, and we're on our way to basic
         * arithmetic. */
        draft_set(zero, "inc", ^(draft_t me, draft_t you) {
            draft_t clone = draft_clone(me);
            return clone;
        });

        /* Walk up the prototype chain to emit a number. */
        draft_set(zero, "print", ^(draft_t me, draft_t you) {
            draft_t parent = me;
            while (parent != zero) {
                printf("S ");
                parent = draft_send(parent, "parent", nil);
            }
            printf("0 ");
            return me;
        });

        printf("zero print ==> ");
        /* Look, we can send messages! */
        draft_send(zero, "print", nil);
        putchar('\n');

        /* And now with a larger number. */
        draft_t eight = zero;
        int i = 8;
        while (i--) {
            printf("eight (%p) inc\n", eight);
            eight = draft_send(eight, "inc", nil);
        }
        printf("eight print ==> ");
        draft_send(eight, "print", nil);
        putchar('\n');

        printf("object quit\n");
        draft_send(draft_object(), "quit", nil);
    }
    return 0;
}

draft_t
draft_clone(draft_t parent)
{
    draft_t clone;
    char label[64];
    snprintf(label, sizeof(label), "<Clone of %p>", parent);
    clone = dispatch_queue_create(label, 0);
    dispatch_set_target_queue(clone, parent);
    draft_set(clone, "parent", ^(draft_t me, draft_t you) {
        return parent;
    });
    draft_log("%s: %p clone -> %p", __func__, parent, clone);
    return clone;
}

void destroy_slot(void *context)
{
    draft_slot_t slot = (__bridge_transfer draft_slot_t)context;
    draft_log("%s: %p dies", __func__, slot);
    (void)slot;  // and now the variable is "used"
}

static const char *s_name_tree;

/* Always returns the same address for a given slot.
 * Required because dispatch specific lookup is by pointer equality only. */
const void *
draft_intern(const char *slot)
{
    typedef int (*t_comp_fn)(const void *, const void *);
    const void *name = tsearch(slot, (void **)&s_name_tree, (t_comp_fn)strcmp);
    return name;
}

/* Sets a slot on an object to a value. */
void
draft_set(draft_t obj, const char *slot, draft_slot_t val)
{
    const void *name = draft_intern(slot);
    dispatch_queue_set_specific(obj,
        name, (__bridge_retained void *)val, destroy_slot);
}

draft_slot_t
draft_lookup_action(draft_t obj, const char *msg)
{
    draft_log("%s: look up \"%s\" from %p", __func__, msg, obj);
    if (!obj) return nil;

    const void *name = draft_intern(msg);

    /* Let GCD get-specific search the prototype chain for us. */
    /* Need to actually execute on the queue to get the prototype
     * search to work. Otherwise it falls back on searching only the
     * current queue. */
    __block draft_slot_t action = NULL;
    dispatch_sync(obj, ^{
        action = (__bridge draft_slot_t)
            dispatch_get_specific(name);
    });

    if (!action) {
        fprintf(stderr, "%s: *** obj %p does not respond to message %s\n",
                __func__, obj, msg);
        return nil;
    }
    draft_log("%s: %p \"%s\": found action %p", __func__, obj, msg, action);
    return action;
}

/* Sends a message to an object. */
draft_t draft_send(draft_t obj, const char *msg, draft_t other)
{
    draft_slot_t action = draft_lookup_action(obj, msg);
    if (!action) return nil;

    draft_log("%s: INVOKE(%s, %p, %p)", __func__, msg, obj, other);
    draft_t result = action(obj, other);
    draft_log("%s: INVOKE(%s, %p, %p) ==> RESULT %p",
              __func__, msg, obj, other, result);
    return result;
}

/* Relays a message up the chain. */
draft_t
draft_super(draft_t obj, const char *msg, draft_t other)
{
    draft_t parent = draft_send(obj, "parent", other);
    draft_slot_t action = draft_lookup_action(parent, msg);
    if (!action) return nil;

    draft_log("%s: SUPER(%s, %p, %p)", __func__, msg, obj, other);
    draft_t result = action(obj, other);
    draft_log("%s: SUPER(%s, %p, %p) ==> RESULT %p",
              __func__, msg, obj, other, result);
    return result;
}

/* Returns the root object. */
draft_t
draft_object(void)
{
    static draft_t object;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        object = dispatch_queue_create("<DraftObject>", 0);
        dispatch_set_target_queue(object, dispatch_get_global_queue(0, 0));
        draft_set(object, "parent", ^draft_t(draft_t me, draft_t you) {
            return NULL;
        });
        draft_set(object, "print", ^draft_t(draft_t me, draft_t you) {
            printf("%p ", me);
            return me;
        });
        draft_set(object, "quit", ^draft_t(draft_t me, draft_t you) {
            exit(0);
        });
    });
    return object;
}
