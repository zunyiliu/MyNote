# Uthread: switching between threads
在这个任务中，我们将为用户级线程系统设计上下文切换机制。

我们需要在用户线程切换前保存callee saved寄存器，并加载另一个线程的寄存器，从而实现切换线程。这里只需要模仿原XV6中的swtch函数即可。

在create函数中，我们先定义好用户线程的栈指针和返回指针。
```C
void   
thread_create(void (*func)())  
{  
  struct thread *t;  
  
  for (t = all_thread; t < all_thread + MAX_THREAD; t++) {  
    if (t->state == FREE) break;  
  }  
  t->state = RUNNABLE;  
  // YOUR CODE HERE  
  t->context.ra = (uint64)func;  
  t->context.sp = (uint64)t->stack + STACK_SIZE;  
}
```

在schedule函数中，我们只需要调用swtch函数即可。
```C
void   
thread_schedule(void)  
{  
  struct thread *t, *next_thread;  
  
  /* Find another runnable thread. */  
  next_thread = 0;  
  t = current_thread + 1;  
  for(int i = 0; i < MAX_THREAD; i++){  
    if(t >= all_thread + MAX_THREAD)  
      t = all_thread;  
    if(t->state == RUNNABLE) {  
      next_thread = t;  
      break;  
    }  
    t = t + 1;  
  }  
  
  if (next_thread == 0) {  
    printf("thread_schedule: no runnable threads\n");  
    exit(-1);  
  }  
  
  if (current_thread != next_thread) {         /* switch threads?  */  
    next_thread->state = RUNNING;  
    t = current_thread;  
    current_thread = next_thread;  
    /* YOUR CODE HERE  
     * Invoke thread_switch to switch from t to next_thread:  
     * thread_switch(??, ??);  
     */  
    thread_switch((uint64)(&t->context),(uint64)(&current_thread->context));  
  } else  
    next_thread = 0;  
}
```

# Using threads
本节任务我们需要修改程序，从而保证程序的并行性。观察后发现是添加key-value时，没有保证散列桶的不变量，因而我们在修改这部分时加锁即可。
```C
//该函数要做的就是将key-value放入到散列表中  
static   
void put(int key, int value)  
{  
    //这里首先将key映射到对应的桶中  
  int i = key % NBUCKET;  
  //这里就开始从对应的桶中找有没有存在的key  
  // is the key already present?  
  struct entry *e = 0;  
  for (e = table[i]; e != 0; e = e->next) {  
    if (e->key == key)  
      break;  
  }  
  //存在就直接更新value  
  if(e){  
    // update the existing key.  
    e->value = value;  
  } else {//否则就采用头插法->问题就出在这里，这里的不变量没有保证  
    // the new is new.  
      pthread_mutex_lock(&locks[i]);  
    insert(key, value, &table[i], table[i]);  
      pthread_mutex_unlock(&locks[i]);  
  }  
}
```

# Barrier
本节任务我们需要修改barrier函数，从而实现coordination。

不是很难，配合题意，看完代码就行。
```C
static void   
barrier()  
{  
  // YOUR CODE HERE  
  //  
  // Block until all threads have called barrier() and  
  // then increment bstate.round.  
  //  
    pthread_mutex_lock(&bstate.barrier_mutex);  
    bstate.nthread += 1;  
    if(bstate.nthread == nthread){  
        bstate.round += 1;  
        bstate.nthread = 0;  
        pthread_mutex_unlock(&bstate.barrier_mutex);  
        pthread_cond_broadcast(&bstate.barrier_cond);  
    }else{  
        pthread_cond_wait(&bstate.barrier_cond,&bstate.barrier_mutex);  
        pthread_mutex_unlock(&bstate.barrier_mutex);  
    }  
}
```