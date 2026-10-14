# 30 Days of AI with Streamlit in Snowflake

Notes from building the early days of the [30 Days of AI](https://30daysofai.streamlit.app/) course on a Snowflake trial account, in Snowsight. The course scripts were written when `claude-3-5-sonnet` was available and when `ai_complete` returned a JSON package. Both of those have changed. The scripts below are the versions that run in the current Snowsight app editor.

The account used here is a GCP trial in `europe-west2`. Cortex stays off until a credit card is saved under **Admin**, then **Billing**. Saving the card does not end the trial. Leave **Upgrade** unclicked. Upgrading ends the free credits and starts billing.

## What kind of app this is

Snowsight now opens Streamlit in a workspace. That app runs in a container. The file list usually contains `streamlit_app.py`, `pyproject.toml`, and `snowflake.yml`. There is no **Packages** button on this screen. The **Packages** button belongs to the older warehouse-style app.

**Run** updates a private preview next to the code. The title on that preview changes only after the script reaches `st.title`. The app opened from **Projects**, then **Streamlit**, keeps the last published copy until you **Deploy**.

Publishing needs a database and a schema. Create them with `sql/create_linkedin_publisher.sql`, then in the workspace click **Deploy** and set the location to `STREAMLIT_APPS.LINKEDIN`.

## Rules that apply to every day

- Draw the title and the form before any Snowflake connection. If the connection runs first and stalls, the preview keeps the previous page, so a new title such as `LinkedIn Post Generator v2` never shows.
- Call the model with Snowpark `ai_complete`. That runs as a warehouse query. `snowflake.cortex.complete` and the OpenAI client call `https://<account>.snowflakecomputing.com/api/v2/cortex/inference:complete`, and this container answers that address with `403 Forbidden`.
- Use the model name `claude-sonnet-4-6`. `claude-3-5-sonnet` was retired on 31 March 2026. `claude-sonnet-5-5` is a preview and is easy for this region to reject.
- `ai_complete` now returns the answer as ordinary text. `json.loads` on that text stops the script before `st.write` can show it.
- `get_active_session()` is the login you already have in Snowsight. A secrets file is only needed when the same script runs on your own computer.
- The final scripts use Snowpark, which is already installed. They do not need the `openai` package or `snowflake-ml-python`.

## Day 1: Connect to Snowflake

Day 1 checks that the app can talk to Snowflake. Inside Snowsight the connection is automatic. The script runs `SELECT CURRENT_VERSION()` and prints the version in a green box.

`session.sql(...).collect()[0][0]` means: run the query, take the first row, take the first column.

```python
import streamlit as st
from snowflake.snowpark.context import get_active_session

st.title("Day 1: Snowflake connection")

try:
    session = get_active_session()
    version = session.sql("SELECT CURRENT_VERSION()").collect()[0][0]
    st.success(f"Successfully connected! Snowflake Version: {version}")
except Exception as error:
    st.error("Could not connect to Snowflake.")
    st.exception(error)
```

## Day 2: Hello, Cortex

Day 2 sends one prompt to a model and shows the reply. The course used `claude-3-5-sonnet` and then `json.loads` on the result. Use `claude-sonnet-4-6` and print the text directly.

`session.range(1)` makes a one-row table so Snowflake has somewhere to run the function. `.select(...)` adds a column named `response`. `.collect()[0][0]` brings that single cell back into Python.

```python
import streamlit as st
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark.functions import ai_complete

st.title("Hello, Cortex!")

prompt = st.text_input("Enter your prompt:", "Explain what a warehouse is in one sentence.")

if st.button("Generate Response"):
    try:
        session = get_active_session()
        answer = session.range(1).select(
            ai_complete(model="claude-sonnet-4-6", prompt=prompt).alias("response")
        ).collect()[0][0]
        st.write("" if answer is None else str(answer))
    except Exception as error:
        st.error("Cortex did not return an answer.")
        st.exception(error)

st.divider()
st.caption("Day 2: Hello, Cortex! | 30 Days of AI")
```

## Day 3: Write streams

The course script does `from openai import OpenAI` and points that client at Snowflake. The word `OpenAI` is a Python library, not an OpenAI account. That library is not installed in the Snowsight container, so the app stops with `No module named 'openai'`. Installing it on your own computer does not change the server at `/opt/streamlit-runtime/`.

`from snowflake.cortex import complete` is a different library. It is also missing until `snowflake-ml-python` is added, and once it is installed it still fails here:

`requests.exceptions.HTTPError: 403 Client Error: Forbidden` for `/api/v2/cortex/inference:complete`.

Live token streaming uses that same address, so this container cannot stream tokens from Claude. The script below gets the full answer through the warehouse, then `st.write_stream` prints it one word at a time.

```python
import streamlit as st
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark.functions import ai_complete

st.title("Write Streams")

llm_models = ["claude-sonnet-4-6", "llama3.1-8b", "mistral-large2"]
model = st.selectbox("Select a model", llm_models)
prompt = st.text_area("Enter prompt", "What is Python?")
streaming_method = st.radio(
    "Streaming Method:",
    ["Direct", "Word by word"],
    help="Direct shows the whole answer at once. Word by word prints it piece by piece.",
)

def words(text):
    for word in text.split():
        yield word + " "

if st.button("Generate Response"):
    try:
        session = get_active_session()
        with st.spinner(f"Generating response with `{model}`"):
            answer = session.range(1).select(
                ai_complete(model=model, prompt=prompt).alias("response")
            ).collect()[0][0]
        text = "" if answer is None else str(answer)
        if streaming_method == "Direct":
            st.write(text)
        else:
            st.write_stream(words(text))
    except Exception as error:
        st.error("The model did not return an answer. Try claude-sonnet-4-6.")
        st.exception(error)

st.divider()
st.caption("Day 3: Write streams | 30 Days of AI")
```

## Day 4: Caching

`@st.cache_data` saves the answer for a prompt. The first **Submit** calls Claude and can take several seconds. The second **Submit**, with the same words, should take about `0.00` seconds. Change one letter and Claude runs again.

The course function also called `json.loads`. That line throws the plain-text answer away, so the cache never stores a result and the page looks empty. Return the sentence itself.

```python
import streamlit as st
import time
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark.functions import ai_complete

st.title("Caching your App")

prompt = st.text_input("Enter your prompt", "Why is the sky blue?")

if st.button("Submit"):
    try:
        session = get_active_session()

        @st.cache_data
        def call_cortex_llm(prompt_text):
            answer = session.range(1).select(
                ai_complete(model="claude-sonnet-4-6", prompt=prompt_text).alias("response")
            ).collect()[0][0]
            return "" if answer is None else str(answer)

        start_time = time.time()
        response = call_cortex_llm(prompt)
        end_time = time.time()
        st.success(f"Call took {end_time - start_time:.2f} seconds")
        st.write(response)
    except Exception as error:
        st.error("The cached call failed.")
        st.exception(error)

st.divider()
st.caption("Day 4: Caching your App | 30 Days of AI")
```

Defining `call_cortex_llm` inside the button keeps the page visible even if Snowflake is slow. The cache still remembers the prompt across clicks in this session.

## Day 5: LinkedIn post generator

The form collects a URL, a tone, and a word count. An f-string stitches those choices into one instruction. Claude returns the post as text, and `st.markdown` renders the line breaks and dash bullets.

The URL is only text in the prompt. This app does not open the webpage. A trial container cannot make that outbound call. The post is based on the address and what the model already knows about the topic.

Click **Generate Post** once and wait. Click it again with the same URL, tone, and word count, and the cached answer returns almost at once. Move the slider and Claude runs again.

```python
import streamlit as st
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark.functions import ai_complete

st.title("LinkedIn Post Generator")

content = st.text_input(
    "Content URL:",
    "https://docs.snowflake.com/en/user-guide/views-semantic/overview",
)
tone = st.selectbox("Tone:", ["Professional", "Casual", "Funny"])
word_count = st.slider("Approximate word count:", 50, 300, 100)

if st.button("Generate Post"):
    try:
        session = get_active_session()
        prompt = f"""
        You are an expert social media manager. Generate a LinkedIn post based on the following:

        Tone: {tone}
        Desired Length: Approximately {word_count} words
        Use content from this URL: {content}

        Generate only the LinkedIn post text. Use dash for bullet points.
        """

        @st.cache_data
        def call_cortex_llm(prompt_text):
            answer = session.range(1).select(
                ai_complete(model="claude-sonnet-4-6", prompt=prompt_text).alias("response")
            ).collect()[0][0]
            return "" if answer is None else str(answer)

        st.subheader("Generated Post:")
        st.markdown(call_cortex_llm(prompt))
    except Exception as error:
        st.error("The post could not be generated.")
        st.exception(error)

st.divider()
st.caption("Day 5: Build a Post Generator App | 30 Days of AI")
```

## Day 6: Status box, and the app to publish

Day 6 adds `st.status`, a box that stays open while Claude works and then collapses with a finished label. The title is `LinkedIn Post Generator v2` so you can see whether the preview picked up the new file.

If that title does not change after **Run**:

1. Confirm the code is in the file whose tab shows the **Run** button. A second file does not change the preview.
2. Look at the preview beside the code. The app under **Projects**, then **Streamlit**, is the last published copy.
3. After the preview shows `v2`, click **Deploy** and choose database `STREAMLIT_APPS` and schema `LINKEDIN`. That published copy is the one that keeps the new title.

```python
import streamlit as st
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark.functions import ai_complete

st.title("LinkedIn Post Generator v2")

content = st.text_input(
    "Content URL:",
    "https://docs.snowflake.com/en/user-guide/views-semantic/overview",
)
tone = st.selectbox("Tone:", ["Professional", "Casual", "Funny"])
word_count = st.slider("Approximate word count:", 50, 300, 100)

if st.button("Generate Post"):
    try:
        session = get_active_session()
        prompt = f"""
        You are an expert social media manager. Generate a LinkedIn post based on the following:

        Tone: {tone}
        Desired Length: Approximately {word_count} words
        Use content from this URL: {content}

        Generate only the LinkedIn post text. Use dash for bullet points.
        """

        with st.status("Starting engine...", expanded=True) as status:
            st.write("Thinking: Analyzing constraints and tone...")
            st.write("Generating: contacting Snowflake Cortex...")
            answer = session.range(1).select(
                ai_complete(model="claude-sonnet-4-6", prompt=prompt).alias("response")
            ).collect()[0][0]
            post = "" if answer is None else str(answer)
            st.write("Post generation completed!")
            status.update(
                label="Post Generated Successfully!",
                state="complete",
                expanded=False,
            )

        st.subheader("Generated Post:")
        st.markdown(post)
    except Exception as error:
        st.error("The post could not be generated.")
        st.exception(error)

st.divider()
st.caption("Day 6: Status UI for Long-Running Task | 30 Days of AI")
```

## Publish the LinkedIn app

1. In Snowsight, open a SQL worksheet and run `sql/create_linkedin_publisher.sql`.
2. The last statement in that file asks Claude for a short hello. A sentence back means the warehouse can run the same call the app uses.
3. Paste the Day 6 script into `streamlit_app.py`.
4. Click **Run**. The private preview title should be `LinkedIn Post Generator v2`.
5. Click **Deploy**. Set the location to `STREAMLIT_APPS` and `LINKEDIN`, and set the query warehouse to `COMPUTE_WH`.
6. Open the app from **Projects**, then **Streamlit**. That view is the published copy.
