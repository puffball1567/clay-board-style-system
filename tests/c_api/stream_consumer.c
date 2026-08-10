#include "cbss.h"

#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

typedef struct StreamWorkerArgs {
  CbssStreamProducer *producer;
  CbssBlob *first;
  CbssBlob *second;
  CbssBlob *rejected;
} StreamWorkerArgs;

typedef struct FailureWorkerArgs {
  CbssStreamProducer *producer;
} FailureWorkerArgs;

static atomic_uint wake_count;

static void wake_ui(void *user_data) {
  atomic_uint *count = user_data;
  atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
}

static void *produce_stream(void *raw_args) {
  StreamWorkerArgs *args = raw_args;
  cbss_thread_attach();
  assert(cbss_stream_producer_open(args->producer) ==
         CBSS_STREAM_OFFER_ACCEPTED);
  assert(cbss_stream_producer_push_blob(args->producer, args->first, 3) ==
         CBSS_STREAM_OFFER_ACCEPTED);
  assert(cbss_stream_producer_progress(args->producer, 3, 6, 1) ==
         CBSS_STREAM_OFFER_ACCEPTED);
  assert(cbss_stream_producer_push_blob(args->producer, args->second, 3) ==
         CBSS_STREAM_OFFER_ACCEPTED);
  assert(cbss_stream_producer_push_blob(args->producer, args->rejected, 3) ==
         CBSS_STREAM_OFFER_BACKPRESSURE);
  assert(cbss_stream_producer_finish(args->producer) ==
         CBSS_STREAM_OFFER_ACCEPTED);
  cbss_stream_producer_release(args->producer);
  cbss_thread_detach();
  return NULL;
}

static void *fail_stream(void *raw_args) {
  FailureWorkerArgs *args = raw_args;
  cbss_thread_attach();
  assert(cbss_stream_producer_open(args->producer) ==
         CBSS_STREAM_OFFER_ACCEPTED);
  assert(cbss_stream_producer_progress(args->producer, 2, 1, 1) ==
         CBSS_STREAM_OFFER_INVALID_ARGUMENT);
  assert(cbss_stream_producer_fail(args->producer, "decoder failed") ==
         CBSS_STREAM_OFFER_ACCEPTED);
  cbss_stream_producer_release(args->producer);
  cbss_thread_detach();
  return NULL;
}

static void assert_blob(CbssBlob *blob, uint8_t expected) {
  uint8_t byte = 0;
  uint32_t read = 0;
  assert(blob != NULL);
  assert(cbss_blob_size(blob) == 1);
  assert(cbss_blob_read(blob, 0, &byte, 1, &read) == CBSS_OK);
  assert(read == 1);
  assert(byte == expected);
  cbss_blob_release(blob);
}

static CbssStreamEvent next_event(CbssBlobStream *stream, uint32_t kind) {
  CbssStreamEvent event;
  memset(&event, 0xCC, sizeof(event));
  assert(cbss_blob_stream_next(stream, &event) == CBSS_OK);
  assert(event.kind == kind);
  return event;
}

int main(void) {
  uint8_t first_byte = 11;
  uint8_t second_byte = 22;
  uint8_t rejected_byte = 33;
  CbssBlob *first = NULL;
  CbssBlob *second = NULL;
  CbssBlob *rejected = NULL;
  assert(cbss_blob_create(&first_byte, 1, NULL, &first) == CBSS_OK);
  assert(cbss_blob_create(&second_byte, 1, NULL, &second) == CBSS_OK);
  assert(cbss_blob_create(&rejected_byte, 1, NULL, &rejected) == CBSS_OK);

  CbssBlobStream *stream = NULL;
  assert(cbss_blob_stream_create(0, 8, &stream) == CBSS_OUT_OF_RANGE);
  assert(stream == NULL);
  assert(cbss_blob_stream_create(8, 8, &stream) == CBSS_OK);
  assert(stream != NULL);

  CbssStreamProducer *producer = NULL;
  assert(cbss_blob_stream_producer(stream, &producer) == CBSS_OK);
  assert(producer != NULL);
  assert(cbss_stream_producer_state(producer) == CBSS_STREAM_IDLE);
  assert(cbss_blob_stream_set_wake_callback(
             stream, wake_ui, &wake_count) == CBSS_OK);
  assert(cbss_stream_producer_retain(producer) == CBSS_OK);

  StreamWorkerArgs args = {
      .producer = producer,
      .first = first,
      .second = second,
      .rejected = rejected,
  };
  pthread_t worker;
  assert(pthread_create(&worker, NULL, produce_stream, &args) == 0);
  assert(pthread_join(worker, NULL) == 0);
  assert(atomic_load_explicit(&wake_count, memory_order_relaxed) == 1u);
  assert(cbss_blob_stream_has_pending(stream));

  CbssStreamPumpResult pumped;
  assert(cbss_blob_stream_pump(stream, 32, &pumped) == CBSS_OK);
  assert(pumped.processed == 5);
  assert(pumped.rejected == 0);
  assert(pumped.changed);
  assert(!pumped.backpressured);
  assert(!pumped.pending);

  CbssStreamEvent event = next_event(stream, CBSS_STREAM_EVENT_OPEN);
  assert(event.blob == NULL);
  event = next_event(stream, CBSS_STREAM_EVENT_DATA);
  assert(event.weight == 3);
  assert_blob(event.blob, first_byte);
  event = next_event(stream, CBSS_STREAM_EVENT_DATA);
  assert(event.weight == 3);
  assert_blob(event.blob, second_byte);
  event = next_event(stream, CBSS_STREAM_EVENT_PROGRESS);
  assert(event.flags & CBSS_STREAM_EVENT_HAS_TOTAL);
  assert(event.completed == 3);
  assert(event.total == 6);
  event = next_event(stream, CBSS_STREAM_EVENT_END);
  assert(event.blob == NULL);
  assert(cbss_blob_stream_next(stream, &event) == CBSS_NOT_AVAILABLE);
  assert(!cbss_blob_stream_has_pending(stream));
  assert(cbss_stream_producer_state(producer) == CBSS_STREAM_ENDED);

  assert(cbss_blob_stream_set_wake_callback(stream, NULL, NULL) == CBSS_OK);
  cbss_blob_stream_destroy(stream);
  assert(cbss_stream_producer_close(producer) == CBSS_STREAM_OFFER_DISPOSED);
  cbss_stream_producer_release(producer);

  CbssBlobStream *pressure_stream = NULL;
  CbssStreamProducer *pressure_producer = NULL;
  assert(cbss_blob_stream_create(2, 2, &pressure_stream) == CBSS_OK);
  assert(cbss_blob_stream_producer(
             pressure_stream, &pressure_producer) == CBSS_OK);
  assert(cbss_stream_producer_open(pressure_producer) ==
         CBSS_STREAM_OFFER_ACCEPTED);
  assert(cbss_stream_producer_push_blob(pressure_producer, first, 1) ==
         CBSS_STREAM_OFFER_ACCEPTED);
  assert(cbss_blob_stream_pump(pressure_stream, 8, &pumped) == CBSS_OK);
  assert(pumped.processed == 2 && !pumped.pending);
  assert(cbss_stream_producer_push_blob(pressure_producer, second, 1) ==
         CBSS_STREAM_OFFER_ACCEPTED);
  assert(cbss_blob_stream_pump(pressure_stream, 8, &pumped) == CBSS_OK);
  assert(pumped.processed == 1 && !pumped.backpressured);
  assert(cbss_stream_producer_push_blob(pressure_producer, rejected, 1) ==
         CBSS_STREAM_OFFER_ACCEPTED);
  assert(cbss_blob_stream_pump(pressure_stream, 8, &pumped) == CBSS_OK);
  assert(pumped.processed == 0);
  assert(pumped.backpressured && pumped.pending);
  (void)next_event(pressure_stream, CBSS_STREAM_EVENT_OPEN);
  event = next_event(pressure_stream, CBSS_STREAM_EVENT_DATA);
  assert_blob(event.blob, first_byte);
  assert(cbss_blob_stream_pump(pressure_stream, 8, &pumped) == CBSS_OK);
  assert(pumped.processed == 1);
  assert(!pumped.backpressured && !pumped.pending);
  event = next_event(pressure_stream, CBSS_STREAM_EVENT_DATA);
  assert_blob(event.blob, second_byte);
  event = next_event(pressure_stream, CBSS_STREAM_EVENT_DATA);
  assert_blob(event.blob, rejected_byte);
  assert(cbss_stream_producer_cancel(pressure_producer) ==
         CBSS_STREAM_OFFER_ACCEPTED);
  assert(cbss_blob_stream_pump(pressure_stream, 8, &pumped) == CBSS_OK);
  (void)next_event(pressure_stream, CBSS_STREAM_EVENT_CANCEL);
  cbss_stream_producer_release(pressure_producer);
  cbss_blob_stream_destroy(pressure_stream);

  cbss_blob_release(first);
  cbss_blob_release(second);
  cbss_blob_release(rejected);

  CbssBlobStream *failed_stream = NULL;
  CbssStreamProducer *failed_producer = NULL;
  assert(cbss_blob_stream_create(4, 1024, &failed_stream) == CBSS_OK);
  assert(cbss_blob_stream_producer(
             failed_stream, &failed_producer) == CBSS_OK);
  assert(cbss_stream_producer_fail(failed_producer, "not open") ==
         CBSS_STREAM_OFFER_INVALID_STATE);
  assert(cbss_stream_producer_retain(failed_producer) == CBSS_OK);
  FailureWorkerArgs failure_args = {.producer = failed_producer};
  assert(pthread_create(&worker, NULL, fail_stream, &failure_args) == 0);
  assert(pthread_join(worker, NULL) == 0);
  assert(cbss_blob_stream_pump(failed_stream, 8, &pumped) == CBSS_OK);
  (void)next_event(failed_stream, CBSS_STREAM_EVENT_OPEN);
  event = next_event(failed_stream, CBSS_STREAM_EVENT_ERROR);
  assert(event.message_bytes == strlen("decoder failed"));
  char error[32];
  assert(cbss_blob_stream_error_message(
             failed_stream, error, sizeof(error)) == strlen("decoder failed"));
  assert(strcmp(error, "decoder failed") == 0);
  cbss_stream_producer_release(failed_producer);
  cbss_blob_stream_destroy(failed_stream);

  assert(cbss_stream_producer_open(NULL) == CBSS_STREAM_OFFER_DISPOSED);
  assert(cbss_stream_producer_push_blob(NULL, NULL, 0) ==
         CBSS_STREAM_OFFER_DISPOSED);
  assert(cbss_blob_stream_next(NULL, &event) == CBSS_INVALID_HANDLE);
  return 0;
}
